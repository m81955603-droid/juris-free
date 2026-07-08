"""
JURIS-FREE Bolivia — API de Clientes (CRM Legal)
Usa httpx directo contra Supabase REST, IMPERSONANDO al usuario autenticado
(no la service key) para que RLS filtre los datos por abogado automaticamente.
"""
from fastapi import APIRouter, HTTPException, Query, Depends
from pydantic import BaseModel
from typing import Optional
import os
import httpx

from ..core.auth import get_current_user, sb_user_headers, CurrentUser

router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")


class ClienteIn(BaseModel):
    nombre: str
    ci_nit:    Optional[str] = None
    telefono:  Optional[str] = None
    email:     Optional[str] = None
    direccion: Optional[str] = None
    ciudad:    Optional[str] = "La Paz"
    tipo:      Optional[str] = "persona_natural"
    notas:     Optional[str] = None


@router.get("/clientes")
async def get_clientes(q: Optional[str] = Query(None), user: CurrentUser = Depends(get_current_user)):
    url = f"{SUPABASE_URL}/rest/v1/clientes?select=*&order=created_at.desc"
    if q:
        url += f"&nombre=ilike.*{q}*"
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.get(url, headers=sb_user_headers(user))
    if r.status_code != 200:
        raise HTTPException(502, f"Error Supabase: {r.text}")
    return r.json()


@router.get("/clientes/{id}")
async def get_cliente(id: str, user: CurrentUser = Depends(get_current_user)):
    """Devuelve cliente + sus casos asociados (solo si pertenecen al usuario)."""
    headers = sb_user_headers(user)
    async with httpx.AsyncClient(timeout=20) as client:
        r_c = await client.get(
            f"{SUPABASE_URL}/rest/v1/clientes?id=eq.{id}&select=*",
            headers=headers
        )
        cliente_data = r_c.json()
        if not cliente_data:
            raise HTTPException(404, "Cliente no encontrado")
        cliente = cliente_data[0]

        nombre = cliente.get("nombre", "")
        r_casos = await client.get(
            f"{SUPABASE_URL}/rest/v1/casos?cliente=ilike.*{nombre}*&select=id,titulo,tipo,estado,fecha_inicio,numero_expediente&order=created_at.desc",
            headers=headers
        )
    casos = r_casos.json() if r_casos.status_code == 200 else []
    return {"cliente": cliente, "casos": casos}


@router.post("/clientes")
async def create_cliente(data: ClienteIn, user: CurrentUser = Depends(get_current_user)):
    payload = data.model_dump(exclude_none=True)
    payload["user_id"] = user.user_id
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(
            f"{SUPABASE_URL}/rest/v1/clientes",
            json=payload,
            headers=sb_user_headers(user)
        )
    if r.status_code not in (200, 201):
        raise HTTPException(502, f"Error creando cliente: {r.text}")
    result = r.json()
    return result[0] if isinstance(result, list) else result


@router.patch("/clientes/{id}")
async def update_cliente(id: str, data: ClienteIn, user: CurrentUser = Depends(get_current_user)):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.patch(
            f"{SUPABASE_URL}/rest/v1/clientes?id=eq.{id}",
            json=data.model_dump(exclude_none=True),
            headers=sb_user_headers(user)
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error actualizando: {r.text}")
    result = r.json()
    return result[0] if isinstance(result, list) and result else {"ok": True}


@router.delete("/clientes/{id}")
async def delete_cliente(id: str, user: CurrentUser = Depends(get_current_user)):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.delete(
            f"{SUPABASE_URL}/rest/v1/clientes?id=eq.{id}",
            headers={**sb_user_headers(user), "Prefer": "return=minimal"}
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error eliminando: {r.text}")
    return {"ok": True}
