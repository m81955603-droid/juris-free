from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import uuid, os, httpx

router = APIRouter()
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_KEY", ""))

def sb_headers():
    return {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json", "Prefer": "return=representation"}

class CaseCreate(BaseModel):
    titulo: str
    cliente: str
    tipo: str
    estado: str = "activo"
    descripcion: Optional[str] = ""
    numero_expediente: Optional[str] = ""
    juzgado: Optional[str] = ""
    contraparte: Optional[str] = ""
    fecha_inicio: Optional[str] = None

class CaseUpdate(BaseModel):
    titulo: Optional[str] = None
    cliente: Optional[str] = None
    tipo: Optional[str] = None
    estado: Optional[str] = None
    descripcion: Optional[str] = None
    numero_expediente: Optional[str] = None
    juzgado: Optional[str] = None
    contraparte: Optional[str] = None

class NoteCreate(BaseModel):
    caso_id: str
    contenido: str
    tipo: str = "nota"

@router.get("/")
async def list_cases(estado: Optional[str]=None, tipo: Optional[str]=None,
                     q: Optional[str]=Query(None), limit: int=50, offset: int=0):
    if not SUPABASE_URL:
        return {"casos": [], "total": 0, "demo": True}
    params = f"select=*&limit={limit}&offset={offset}&order=created_at.desc"
    if estado: params += f"&estado=eq.{estado}"
    if tipo:   params += f"&tipo=eq.{tipo}"
    if q:      params += f"&or=(titulo.ilike.*{q}*,cliente.ilike.*{q}*)"
    async with httpx.AsyncClient() as c:
        r = await c.get(f"{SUPABASE_URL}/rest/v1/casos?{params}", headers=sb_headers())
    if r.status_code not in (200, 206):
        raise HTTPException(502, r.text)
    return {"casos": r.json(), "total": len(r.json())}

@router.post("/")
async def create_case(body: CaseCreate):
    payload = body.dict()
    payload["id"] = str(uuid.uuid4())
    payload["created_at"] = datetime.utcnow().isoformat()
    payload["fecha_inicio"] = payload.get("fecha_inicio") or datetime.utcnow().date().isoformat()
    if not SUPABASE_URL:
        return {"caso": payload, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.post(f"{SUPABASE_URL}/rest/v1/casos", json=payload, headers=sb_headers())
    if r.status_code not in (200, 201):
        raise HTTPException(502, r.text)
    return {"caso": r.json()[0] if isinstance(r.json(), list) else r.json()}

@router.get("/{caso_id}")
async def get_case(caso_id: str):
    if not SUPABASE_URL:
        return {"caso": None, "notas": [], "timeline": [], "demo": True}
    async with httpx.AsyncClient() as c:
        r1 = await c.get(f"{SUPABASE_URL}/rest/v1/casos?id=eq.{caso_id}&select=*", headers=sb_headers())
        r2 = await c.get(f"{SUPABASE_URL}/rest/v1/caso_notas?caso_id=eq.{caso_id}&order=created_at.desc", headers=sb_headers())
        r3 = await c.get(f"{SUPABASE_URL}/rest/v1/caso_timeline?caso_id=eq.{caso_id}&order=fecha.desc", headers=sb_headers())
    casos = r1.json()
    if not casos: raise HTTPException(404, "Caso no encontrado")
    return {"caso": casos[0], "notas": r2.json(), "timeline": r3.json()}

@router.patch("/{caso_id}")
async def update_case(caso_id: str, body: CaseUpdate):
    payload = {k: v for k, v in body.dict().items() if v is not None}
    payload["updated_at"] = datetime.utcnow().isoformat()
    if not SUPABASE_URL: return {"ok": True, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.patch(f"{SUPABASE_URL}/rest/v1/casos?id=eq.{caso_id}", json=payload, headers=sb_headers())
    if r.status_code not in (200, 204): raise HTTPException(502, r.text)
    return {"ok": True}

@router.delete("/{caso_id}")
async def delete_case(caso_id: str):
    if not SUPABASE_URL: return {"ok": True, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.delete(f"{SUPABASE_URL}/rest/v1/casos?id=eq.{caso_id}", headers=sb_headers())
    if r.status_code not in (200, 204): raise HTTPException(502, r.text)
    return {"ok": True}

@router.post("/{caso_id}/notas")
async def add_note(caso_id: str, body: NoteCreate):
    payload = {"id": str(uuid.uuid4()), "caso_id": caso_id,
               "contenido": body.contenido, "tipo": body.tipo,
               "created_at": datetime.utcnow().isoformat()}
    if not SUPABASE_URL: return {"nota": payload, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.post(f"{SUPABASE_URL}/rest/v1/caso_notas", json=payload, headers=sb_headers())
    if r.status_code not in (200, 201): raise HTTPException(502, r.text)
    return {"nota": r.json()[0] if isinstance(r.json(), list) else payload}
