"""
JURIS-FREE Bolivia — API de Clientes (CRM Legal)
Usa httpx directo contra Supabase REST (compatible con nuevas API keys sb_secret_...)
"""
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
import os, httpx, logging

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")

def sb_headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


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
async def get_clientes(q: Optional[str] = Query(None)):
    url = f"{SUPABASE_URL}/rest/v1/clientes?select=*&order=created_at.desc"
    if q:
        url += f"&nombre=ilike.*{q}*"
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.get(url, headers=sb_headers())
    if r.status_code != 200:
        raise HTTPException(502, f"Error Supabase: {r.text}")
    return r.json()


@router.get("/clientes/{id}")
async def get_cliente(id: str):
    """Devuelve cliente + sus casos asociados."""
    async with httpx.AsyncClient(timeout=20) as client:
        # Cliente
        r_c = await client.get(
            f"{SUPABASE_URL}/rest/v1/clientes?id=eq.{id}&select=*",
            headers=sb_headers()
        )
        # Casos vinculados por nombre del cliente
        cliente_data = r_c.json()
        if not cliente_data:
            raise HTTPException(404, "Cliente no encontrado")
        cliente = cliente_data[0]

        # Buscar casos donde cliente coincide con el nombre
        nombre = cliente.get("nombre", "")
        r_casos = await client.get(
            f"{SUPABASE_URL}/rest/v1/casos?cliente=ilike.*{nombre}*&select=id,titulo,tipo,estado,fecha_inicio,numero_expediente&order=created_at.desc",
            headers=sb_headers()
        )
    casos = r_casos.json() if r_casos.status_code == 200 else []
    return {"cliente": cliente, "casos": casos}


@router.post("/clientes")
async def create_cliente(data: ClienteIn):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(
            f"{SUPABASE_URL}/rest/v1/clientes",
            json=data.model_dump(exclude_none=True),
            headers=sb_headers()
        )
    if r.status_code not in (200, 201):
        raise HTTPException(502, f"Error creando cliente: {r.text}")
    result = r.json()
    return result[0] if isinstance(result, list) else result


@router.patch("/clientes/{id}")
async def update_cliente(id: str, data: ClienteIn):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.patch(
            f"{SUPABASE_URL}/rest/v1/clientes?id=eq.{id}",
            json=data.model_dump(exclude_none=True),
            headers=sb_headers()
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error actualizando: {r.text}")
    result = r.json()
    return result[0] if isinstance(result, list) and result else {"ok": True}


@router.delete("/clientes/{id}")
async def delete_cliente(id: str):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.delete(
            f"{SUPABASE_URL}/rest/v1/clientes?id=eq.{id}",
            headers={**sb_headers(), "Prefer": "return=minimal"}
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error eliminando: {r.text}")
    return {"ok": True}
