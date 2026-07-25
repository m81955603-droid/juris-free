"""
JURIS-FREE Bolivia — Panel de administracion
Permite al/los administrador(es) ver, aprobar o rechazar el acceso de
nuevos abogados al sistema.

Estas rutas SI usan la Service Key (a diferencia del resto del backend),
porque un admin necesita ver la lista de TODOS los usuarios, algo que
RLS normal no permite. Por seguridad, cada endpoint primero confirma
que quien llama es admin (usando su propio token, respetando RLS) antes
de usar la service key para la operacion real.
"""
import os
import logging
from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, HTTPException, Depends

from ..core.auth import get_current_user, CurrentUser

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")


def _admin_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _exigir_admin(user: CurrentUser):
    if not user.es_admin:
        raise HTTPException(403, "Solo un administrador puede realizar esta acción.")


@router.get("/usuarios")
async def listar_usuarios(user: CurrentUser = Depends(get_current_user)):
    """Lista todos los abogados registrados (solo admin)."""
    _exigir_admin(user)
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?select=*&order=fecha_registro.desc",
            headers=_admin_headers()
        )
    if r.status_code != 200:
        raise HTTPException(502, f"Error consultando usuarios: {r.text}")
    return r.json()


@router.post("/usuarios/{usuario_id}/aprobar")
async def aprobar_usuario(usuario_id: str, user: CurrentUser = Depends(get_current_user)):
    _exigir_admin(user)
    payload = {
        "estado": "aprobado",
        "fecha_aprobacion": datetime.now(timezone.utc).isoformat(),
        "aprobado_por": user.user_id,
    }
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.patch(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?id=eq.{usuario_id}",
            json=payload,
            headers=_admin_headers()
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error aprobando usuario: {r.text}")
    return {"ok": True}


@router.post("/usuarios/{usuario_id}/rechazar")
async def rechazar_usuario(usuario_id: str, user: CurrentUser = Depends(get_current_user)):
    _exigir_admin(user)
    payload = {"estado": "rechazado"}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.patch(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?id=eq.{usuario_id}",
            json=payload,
            headers=_admin_headers()
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error rechazando usuario: {r.text}")
    return {"ok": True}


@router.post("/usuarios/{usuario_id}/hacer-admin")
async def hacer_admin(usuario_id: str, user: CurrentUser = Depends(get_current_user)):
    """Asciende a otro abogado a administrador (solo un admin puede hacerlo)."""
    _exigir_admin(user)
    payload = {"rol": "admin"}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.patch(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?id=eq.{usuario_id}",
            json=payload,
            headers=_admin_headers()
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error actualizando rol: {r.text}")
    return {"ok": True}


@router.get("/mi-estado")
async def mi_estado(user: CurrentUser = Depends(get_current_user)):
    """El propio abogado consulta su estado de aprobacion (para la pantalla de espera)."""
    return {
        "rol": user.rol,
        "estado": user.estado,
        "en_prueba": user.en_prueba,
        "minutos_restantes": user.minutos_restantes,
    }
