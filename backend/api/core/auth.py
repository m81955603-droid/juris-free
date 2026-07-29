"""
JURIS-FREE Bolivia — Autenticacion de backend
Valida el JWT que manda el frontend (token de sesion de Supabase) llamando
al endpoint /auth/v1/user de Supabase, y construye headers para llamar a
PostgREST IMPERSONANDO al usuario, para que las policies de Row Level
Security se apliquen de verdad.

Ademas, verifica el estado de aprobacion del abogado (usuarios_perfil):
- aprobado   -> acceso completo
- pendiente  -> acceso de prueba por 1 hora desde el registro, luego bloqueado
- rechazado  -> bloqueado siempre

SUPER ADMIN: a diferencia de "aprobado/rechazado" (que se guarda en la
base de datos y se puede editar desde botones de la app), quien es
super-admin se decide SOLO por la variable de entorno SUPER_ADMIN_EMAILS
configurada en Render. Nadie puede volverse super-admin desde la app,
ni aunque manipule la base de datos o el navegador — hay que tener
acceso al panel de Render para cambiar esa lista.

Por que se valida el JWT llamando a Supabase en vez de verificarlo local:
el proyecto usa el sistema nuevo de "JWT Signing Keys" (rotacion de llaves,
posiblemente asimetricas). Pedirle a Supabase que verifique el token evita
tener que manejar algoritmos/rotacion de llaves en el backend.

IMPORTANTE: nunca usar SUPABASE_SERVICE_KEY para leer/escribir datos
de un abogado especifico (casos, clientes, plantillas, eventos, notas).
La service key ignora RLS por diseno — solo debe usarse para tareas
administrativas puntuales (ver backend/api/routes/admin.py), nunca
para responder una request normal de usuario.
"""
import os
import base64
import json
import logging
from datetime import datetime, timezone
import httpx
from fastapi import Header, HTTPException

logger = logging.getLogger(__name__)

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

MINUTOS_PRUEBA_PENDIENTE = 60  # 1 hora de acceso mientras se aprueba la cuenta

# Lista fija de super-admins, configurada SOLO en Render (Environment
# Variables), nunca editable desde la app. Formato: emails separados
# por coma. Ej: "m81955603@gmail.com,otro@gmail.com"
_SUPER_ADMIN_EMAILS = {
    e.strip().lower()
    for e in os.getenv("SUPER_ADMIN_EMAILS", "").split(",")
    if e.strip()
}


def es_email_super_admin(email: str | None) -> bool:
    """Util para otros modulos (ej. admin.py) que necesiten marcar filas
    de la lista de usuarios segun quien es realmente super-admin."""
    return bool(email) and email.strip().lower() in _SUPER_ADMIN_EMAILS


def _leer_session_id_del_token(token: str) -> str | None:
    """
    Lee el campo 'session_id' del JWT SIN verificar su firma — es seguro
    porque en este punto el token ya fue validado llamando a Supabase
    (/auth/v1/user). Solo se usa para leer ese dato, no para autenticar.
    Supabase incluye un session_id distinto por cada login.
    """
    try:
        partes = token.split(".")
        if len(partes) != 3:
            return None
        payload_b64 = partes[1]
        relleno = "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + relleno))
        return payload.get("session_id")
    except Exception:
        return None


class CurrentUser:
    """Representa al abogado autenticado en la request actual."""
    def __init__(self, user_id: str, token: str, email: str | None = None,
                 estado: str = "pendiente",
                 en_prueba: bool = False, minutos_restantes: int = 0):
        self.user_id = user_id
        self.token = token
        self.email = email
        self.estado = estado
        self.en_prueba = en_prueba
        self.minutos_restantes = minutos_restantes

    @property
    def es_super_admin(self) -> bool:
        return es_email_super_admin(self.email)


async def get_current_user(authorization: str = Header(None)) -> CurrentUser:
    """
    Dependency de FastAPI. Usar como: user: CurrentUser = Depends(get_current_user)

    1. Valida el JWT contra Supabase.
    2. Busca (o crea si falta) el perfil del usuario en usuarios_perfil.
    3. Bloquea el acceso si esta rechazado, o si esta pendiente y ya
       se le acabo la hora de prueba.

    NOTA: los super-admins (ver SUPER_ADMIN_EMAILS) SIEMPRE pasan sin
    restricciones de estado/prueba, para que nunca se puedan quedar
    fuera del sistema por error.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Falta el token de autenticacion. Inicia sesion nuevamente.")

    token = authorization[len("Bearer "):].strip()

    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        logger.error("SUPABASE_URL o SUPABASE_ANON_KEY no configurados en el backend")
        raise HTTPException(500, "Backend mal configurado: falta SUPABASE_URL o SUPABASE_ANON_KEY")

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(
            f"{SUPABASE_URL}/auth/v1/user",
            headers={"Authorization": f"Bearer {token}", "apikey": SUPABASE_ANON_KEY}
        )

        if r.status_code != 200:
            raise HTTPException(401, "Tu sesion expiro o el token es invalido. Vuelve a iniciar sesion.")

        data = r.json()
        user_id = data.get("id")
        email = data.get("email")
        if not user_id:
            raise HTTPException(401, "Token sin usuario asociado.")

        es_super_admin = es_email_super_admin(email)

        headers = {
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        r_perfil = await client.get(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?id=eq.{user_id}&select=*",
            headers=headers
        )
        perfiles = r_perfil.json() if r_perfil.status_code == 200 else []

        if not perfiles:
            # Perfil no existe todavia (carrera con el trigger, o cuenta muy vieja).
            # Lo creamos nosotros mismos, impersonando al usuario (RLS lo permite).
            nombre = (data.get("user_metadata") or {}).get("full_name", "")
            payload = {"id": user_id, "email": email, "nombre": nombre}
            r_crear = await client.post(
                f"{SUPABASE_URL}/rest/v1/usuarios_perfil",
                json=payload,
                headers={**headers, "Prefer": "return=representation"}
            )
            perfiles = r_crear.json() if r_crear.status_code in (200, 201) else [{
                "estado": "pendiente", "fecha_registro": datetime.now(timezone.utc).isoformat()
            }]

    perfil = perfiles[0]
    estado = perfil.get("estado", "pendiente")
    fecha_registro_str = perfil.get("fecha_registro")

    en_prueba = False
    minutos_restantes = 0

    if es_super_admin:
        # El super-admin nunca queda bloqueado, pase lo que pase en la tabla.
        return CurrentUser(user_id=user_id, token=token, email=email,
                            estado="aprobado", en_prueba=False, minutos_restantes=0)

    if estado == "rechazado":
        raise HTTPException(403, "Tu cuenta fue rechazada. Contacta al administrador del sistema.")

    if estado == "pendiente":
        try:
            fecha_registro = datetime.fromisoformat(fecha_registro_str.replace("Z", "+00:00"))
        except Exception:
            fecha_registro = datetime.now(timezone.utc)

        minutos_transcurridos = (datetime.now(timezone.utc) - fecha_registro).total_seconds() / 60
        minutos_restantes = max(0, round(MINUTOS_PRUEBA_PENDIENTE - minutos_transcurridos))

        if minutos_transcurridos > MINUTOS_PRUEBA_PENDIENTE:
            raise HTTPException(
                403,
                "Tu hora de prueba terminó. Tu cuenta sigue pendiente de aprobación por el administrador."
            )
        en_prueba = True

    # ── SESION UNICA: si esta cuenta inicio sesion en otro dispositivo
    # despues que esta, esta sesion queda invalidada. El super-admin
    # esta exento (puede tener varias sesiones propias abiertas).
    session_id_actual = _leer_session_id_del_token(token)
    session_id_guardado = perfil.get("sesion_activa_id")
    if session_id_actual and session_id_guardado and session_id_guardado != session_id_actual:
        raise HTTPException(
            401,
            "Tu sesión se cerró porque esta cuenta inició sesión en otro dispositivo."
        )

    return CurrentUser(
        user_id=user_id, token=token, email=email,
        estado=estado, en_prueba=en_prueba, minutos_restantes=minutos_restantes
    )


def sb_user_headers(user: CurrentUser) -> dict:
    """
    Headers para llamar a PostgREST de Supabase IMPERSONANDO al usuario
    autenticado (no como admin). Con esto, Supabase aplica las policies
    de RLS usando auth.uid() = user.user_id automaticamente.
    """
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {user.token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
