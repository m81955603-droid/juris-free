from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import os

router = APIRouter()

# Usar Supabase para clientes
from supabase import create_client

supabase = create_client(
    os.getenv("SUPABASE_URL", ""),
    os.getenv("SUPABASE_SERVICE_KEY", "")
)

class Cliente(BaseModel):
    nombre: str
    telefono: Optional[str] = None
    email: Optional[str] = None
    direccion: Optional[str] = None
    notas: Optional[str] = None

@router.get("/clientes")
async def get_clientes():
    try:
        res = supabase.table("clientes").select("*").order("created_at", desc=True).execute()
        return res.data
    except Exception as e:
        raise HTTPException(500, str(e))

@router.post("/clientes")
async def create_cliente(cliente: Cliente):
    try:
        res = supabase.table("clientes").insert(cliente.dict()).execute()
        return res.data[0]
    except Exception as e:
        raise HTTPException(500, str(e))

@router.put("/clientes/{id}")
async def update_cliente(id: str, cliente: Cliente):
    try:
        res = supabase.table("clientes").update(cliente.dict()).eq("id", id).execute()
        return res.data[0]
    except Exception as e:
        raise HTTPException(500, str(e))

@router.delete("/clientes/{id}")
async def delete_cliente(id: str):
    try:
        supabase.table("clientes").delete().eq("id", id).execute()
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))
