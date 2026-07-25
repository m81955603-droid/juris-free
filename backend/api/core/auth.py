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
import logging
from datetime import datetime, timezone
import httpx
from fastapi import Header, HTTPException

logger = logging.getLogger(__name__)

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

MINUTOS_PRUEBA_PENDIENTE = 60  # 1 hora de acceso mientras se aprueba la cuenta


class CurrentUser:
    """Representa al abogado autenticado en la request actual."""
    def __init__(self, user_id: str, token: str, email: str | None = None,
                 rol: str = "abogado", estado: str = "pendiente",
                 en_prueba: bool = False, minutos_restantes: int = 0):
        self.user_id = user_id
        self.token = token
        self.email = email
        self.rol = rol
        self.estado = estado
        self.en_prueba = en_prueba
        self.minutos_restantes = minutos_restantes

    @property
    def es_admin(self) -> bool:
        return self.rol == "admin"


async def get_current_user(authorization: str = Header(None)) -> CurrentUser:
    """
    Dependency de FastAPI. Usar como: user: CurrentUser = Depends(get_current_user)

    1. Valida el JWT contra Supabase.
    2. Busca (o crea si falta) el perfil del usuario en usuarios_perfil.
    3. Bloquea el acceso si esta rechazado, o si esta pendiente y ya
       se le acabo la hora de prueba.
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
                "rol": "abogado", "estado": "pendiente", "fecha_registro": datetime.now(timezone.utc).isoformat()
            }]

    perfil = perfiles[0]
    rol = perfil.get("rol", "abogado")
    estado = perfil.get("estado", "pendiente")
    fecha_registro_str = perfil.get("fecha_registro")

    en_prueba = False
    minutos_restantes = 0

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

    return CurrentUser(
        user_id=user_id, token=token, email=email,
        rol=rol, estado=estado, en_prueba=en_prueba, minutos_restantes=minutos_restantes
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
