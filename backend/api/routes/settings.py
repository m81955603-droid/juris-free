"""
JURIS-FREE Bolivia — Ajustes personales del abogado
Permite a cada abogado configurar sus propias API keys de IA (Gemini,
Groq, etc.), que la cascada de llm.py/ocr.py usara en vez de las
claves compartidas del sistema.

No se devuelve el valor real de las claves ya guardadas al frontend
(solo si estan configuradas o no) para no re-exponer secretos en cada
consulta; para "cambiar" una clave, el abogado simplemente escribe una
nueva encima.
"""
import os
import logging
from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional

from ..core.auth import get_current_user, sb_user_headers, CurrentUser
from ..core.user_keys import PROVIDER_COLUMNS

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")


class ApiKeysUpdate(BaseModel):
    gemini_api_key: Optional[str] = None
    groq_api_key: Optional[str] = None
    cerebras_api_key: Optional[str] = None
    openrouter_api_key: Optional[str] = None
    sambanova_api_key: Optional[str] = None
    mistral_api_key: Optional[str] = None


@router.get("/api-keys")
async def obtener_estado_api_keys(user: CurrentUser = Depends(get_current_user)):
    """Devuelve solo si cada proveedor esta configurado (true/false), nunca el valor real."""
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(
            f"{SUPABASE_URL}/rest/v1/usuario_api_keys?user_id=eq.{user.user_id}&select=*",
            headers=sb_user_headers(user)
        )
    fila = {}
    if r.status_code == 200:
        filas = r.json()
        if filas:
            fila = filas[0]

    return {
        proveedor: bool(fila.get(columna))
        for proveedor, columna in PROVIDER_COLUMNS.items()
    }


@router.post("/api-keys")
async def guardar_api_keys(body: ApiKeysUpdate, user: CurrentUser = Depends(get_current_user)):
    """
    Guarda (o actualiza) las claves que el abogado envie. Los campos que
    vengan vacios ('') se limpian; los que vengan como None (no enviados)
    no se tocan.
    """
    payload = {k: v for k, v in body.model_dump().items() if v is not None}
    if not payload:
        raise HTTPException(400, "No se envio ninguna clave para guardar.")

    payload["user_id"] = user.user_id
    payload["updated_at"] = datetime.now(timezone.utc).isoformat()

    headers = sb_user_headers(user)
    headers["Prefer"] = "resolution=merge-duplicates,return=representation"

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.post(
            f"{SUPABASE_URL}/rest/v1/usuario_api_keys",
            json=payload,
            headers=headers
        )
    if r.status_code not in (200, 201):
        raise HTTPException(502, f"No se pudieron guardar las claves: {r.text}")
    return {"ok": True}


@router.delete("/api-keys/{proveedor}")
async def borrar_api_key(proveedor: str, user: CurrentUser = Depends(get_current_user)):
    """Borra (deja en blanco) la clave de un proveedor especifico, volviendo al respaldo del sistema."""
    columna = PROVIDER_COLUMNS.get(proveedor)
    if not columna:
        raise HTTPException(400, f"Proveedor desconocido: {proveedor}")

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.patch(
            f"{SUPABASE_URL}/rest/v1/usuario_api_keys?user_id=eq.{user.user_id}",
            json={columna: None},
            headers=sb_user_headers(user)
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"No se pudo borrar la clave: {r.text}")
    return {"ok": True}
