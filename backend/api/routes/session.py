"""
JURIS-FREE Bolivia / ALSAMI — Registro de sesion unica
Se llama justo despues de iniciar sesion (email/password o Google).
Marca la sesion actual como la UNICA valida para esa cuenta; cualquier
otra sesion abierta antes en otro dispositivo queda invalidada en su
siguiente peticion (ver core/auth.py -> get_current_user).
"""
import os
import logging

import httpx
from fastapi import APIRouter, Header, HTTPException

from ..core.auth import SUPABASE_ANON_KEY, _leer_session_id_del_token

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")


@router.post("/registrar")
async def registrar_sesion(authorization: str = Header(None)):
    """
    Valida el token contra Supabase (igual que get_current_user) y
    guarda el session_id de ESTA sesion como la valida para la cuenta.
    No usa get_current_user porque, a proposito, este endpoint no debe
    fallar por "sesion invalidada" — es justo el que la vuelve valida.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Falta el token de autenticacion.")
    token = authorization[len("Bearer "):].strip()

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(
            f"{SUPABASE_URL}/auth/v1/user",
            headers={"Authorization": f"Bearer {token}", "apikey": SUPABASE_ANON_KEY}
        )
        if r.status_code != 200:
            raise HTTPException(401, "Token invalido.")
        user_id = r.json().get("id")

        session_id = _leer_session_id_del_token(token)
        if not session_id or not user_id:
            return {"ok": False}

        headers = {
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
        await client.patch(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?id=eq.{user_id}",
            json={"sesion_activa_id": session_id},
            headers=headers
        )

    return {"ok": True}
