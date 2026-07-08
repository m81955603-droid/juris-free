"""
JURIS-FREE Bolivia — Autenticacion de backend
Valida el JWT que manda el frontend (token de sesion de Supabase) llamando
al endpoint /auth/v1/user de Supabase, y construye headers para llamar a
PostgREST IMPERSONANDO al usuario, para que las policies de Row Level
Security se apliquen de verdad.

Por que se valida llamando a Supabase en vez de verificar el JWT localmente:
el proyecto usa el sistema nuevo de "JWT Signing Keys" (rotacion de llaves,
posiblemente asimetricas). Pedirle a Supabase que verifique el token evita
tener que manejar algoritmos/rotacion de llaves en el backend, y sigue
funcionando aunque Supabase rote las llaves de firma en el futuro.

IMPORTANTE: nunca usar SUPABASE_SERVICE_KEY para leer/escribir datos
de un abogado especifico (casos, clientes, plantillas, eventos, notas).
La service key ignora RLS por diseno — solo debe usarse para tareas
de sistema (ej. cron jobs, migraciones), nunca en una request de usuario.
"""
import os
import logging
import httpx
from fastapi import Header, HTTPException

logger = logging.getLogger(__name__)

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")


class CurrentUser:
    """Representa al abogado autenticado en la request actual."""
    def __init__(self, user_id: str, token: str, email: str | None = None):
        self.user_id = user_id
        self.token = token
        self.email = email


async def get_current_user(authorization: str = Header(None)) -> CurrentUser:
    """
    Dependency de FastAPI. Usar como: user: CurrentUser = Depends(get_current_user)

    Extrae el JWT del header 'Authorization: Bearer <token>' que el
    interceptor de Angular agrega a cada request, y le pregunta a
    Supabase si es valido y de que usuario es.
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
    if not user_id:
        raise HTTPException(401, "Token sin usuario asociado.")

    return CurrentUser(user_id=user_id, token=token, email=data.get("email"))


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
