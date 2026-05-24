from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import os

router = APIRouter()

class Cliente(BaseModel):
    nombre: str
    telefono: Optional[str] = None
    email: Optional[str] = None
    direccion: Optional[str] = None
    notas: Optional[str] = None

def get_supabase():
    from supabase import create_client
    return create_client(
        os.getenv("SUPABASE_URL", ""),
        os.getenv("SUPABASE_SERVICE_KEY", "")
    )

@router.get("/clientes")
async def get_clientes():
    try:
        res = get_supabase().table("clientes").select("*").order("created_at", desc=True).execute()
        return res.data
    except Exception as e:
        raise HTTPException(500, str(e))

@router.post("/clientes")
async def create_cliente(cliente: Cliente):
    try:
        res = get_supabase().table("clientes").insert(cliente.dict()).execute()
        return res.data[0]
    except Exception as e:
        raise HTTPException(500, str(e))

@router.put("/clientes/{id}")
async def update_cliente(id: str, cliente: Cliente):
    try:
        res = get_supabase().table("clientes").update(cliente.dict()).eq("id", id).execute()
        return res.data[0]
    except Exception as e:
        raise HTTPException(500, str(e))

@router.delete("/clientes/{id}")
async def delete_cliente(id: str):
    try:
        get_supabase().table("clientes").delete().eq("id", id).execute()
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))
