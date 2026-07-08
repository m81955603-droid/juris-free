from fastapi import APIRouter, HTTPException, Query, Depends
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timedelta, date
import uuid, os
import httpx

from ..core.auth import get_current_user, sb_user_headers, CurrentUser

router = APIRouter()
SUPABASE_URL = os.getenv("SUPABASE_URL", "")

PLAZOS = {
    "apelacion_civil":      {"dias": 10, "norma": "Art. 261 CPC"},
    "apelacion_penal":      {"dias": 5,  "norma": "Art. 403 CPP"},
    "contestacion_demanda": {"dias": 30, "norma": "Art. 365 CPC"},
    "casacion":             {"dias": 10, "norma": "Art. 273 CPC"},
    "excepcion_previa":     {"dias": 15, "norma": "Art. 366 CPC"},
    "recurso_reposicion":   {"dias": 3,  "norma": "Art. 252 CPC"},
}

class EventCreate(BaseModel):
    titulo: str
    descripcion: Optional[str] = ""
    fecha_inicio: str
    hora: Optional[str] = "09:00"
    tipo: str = "audiencia"
    caso_id: Optional[str] = None
    color: Optional[str] = "#2563eb"

class PlazoCalc(BaseModel):
    tipo_plazo: str
    fecha_inicio: str
    caso_id: Optional[str] = None

class EventUpdate(BaseModel):
    titulo: Optional[str] = None
    fecha_inicio: Optional[str] = None
    hora: Optional[str] = None
    tipo: Optional[str] = None
    completado: Optional[bool] = None

@router.get("/plazos-bolivianos")
async def get_plazos():
    return {"plazos": PLAZOS}

@router.get("/proximos-vencimientos")
async def upcoming(dias: int = 7, user: CurrentUser = Depends(get_current_user)):
    hoy = date.today()
    tope = hoy + timedelta(days=dias)
    if not SUPABASE_URL: return {"vencimientos": [], "demo": True}
    params = f"select=*&fecha_inicio=gte.{hoy}&fecha_inicio=lte.{tope}&completado=eq.false&order=fecha_inicio.asc"
    async with httpx.AsyncClient() as c:
        r = await c.get(f"{SUPABASE_URL}/rest/v1/calendario_eventos?{params}", headers=sb_user_headers(user))
    return {"vencimientos": r.json() if r.status_code in (200,206) else []}

@router.get("/")
async def list_events(mes: Optional[int]=None, anio: Optional[int]=None,
                      caso_id: Optional[str]=None, limit: int=100,
                      user: CurrentUser = Depends(get_current_user)):
    if not SUPABASE_URL:
        hoy = date.today()
        return {"eventos": [
            {"id":"d1","titulo":"Audiencia ejemplo","fecha_inicio":(hoy+timedelta(2)).isoformat(),"hora":"09:00","tipo":"audiencia","color":"#2563eb","completado":False},
            {"id":"d2","titulo":"Vence apelacion","fecha_inicio":(hoy+timedelta(5)).isoformat(),"hora":"23:59","tipo":"vencimiento","color":"#dc2626","completado":False},
        ], "plazos_tipos": list(PLAZOS.keys())}
    params = f"select=*&limit={limit}&order=fecha_inicio.asc"
    if caso_id: params += f"&caso_id=eq.{caso_id}"
    if mes and anio:
        ultimo = (date(anio,mes,1).replace(day=28)+timedelta(4)).replace(day=1)-timedelta(1)
        params += f"&fecha_inicio=gte.{anio}-{mes:02d}-01&fecha_inicio=lte.{ultimo}"
    async with httpx.AsyncClient() as c:
        r = await c.get(f"{SUPABASE_URL}/rest/v1/calendario_eventos?{params}", headers=sb_user_headers(user))
    if r.status_code not in (200,206): raise HTTPException(502, r.text)
    return {"eventos": r.json(), "plazos_tipos": list(PLAZOS.keys())}

@router.post("/")
async def create_event(body: EventCreate, user: CurrentUser = Depends(get_current_user)):
    payload = body.dict()
    payload["id"] = str(uuid.uuid4())
    payload["user_id"] = user.user_id
    payload["completado"] = False
    payload["created_at"] = datetime.utcnow().isoformat()
    if not SUPABASE_URL: return {"evento": payload, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.post(f"{SUPABASE_URL}/rest/v1/calendario_eventos", json=payload, headers=sb_user_headers(user))
    if r.status_code not in (200,201): raise HTTPException(502, r.text)
    return {"evento": r.json()[0] if isinstance(r.json(),list) else payload}

@router.patch("/{evento_id}")
async def update_event(evento_id: str, body: EventUpdate, user: CurrentUser = Depends(get_current_user)):
    payload = {k:v for k,v in body.dict().items() if v is not None}
    if not SUPABASE_URL: return {"ok": True, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.patch(f"{SUPABASE_URL}/rest/v1/calendario_eventos?id=eq.{evento_id}", json=payload, headers=sb_user_headers(user))
    if r.status_code not in (200,204): raise HTTPException(502, r.text)
    return {"ok": True}

@router.delete("/{evento_id}")
async def delete_event(evento_id: str, user: CurrentUser = Depends(get_current_user)):
    if not SUPABASE_URL: return {"ok": True, "demo": True}
    async with httpx.AsyncClient() as c:
        r = await c.delete(f"{SUPABASE_URL}/rest/v1/calendario_eventos?id=eq.{evento_id}", headers=sb_user_headers(user))
    if r.status_code not in (200,204): raise HTTPException(502, r.text)
    return {"ok": True}

@router.post("/calcular-plazo")
async def calc_plazo(body: PlazoCalc):
    if body.tipo_plazo not in PLAZOS:
        raise HTTPException(400, f"Opciones: {list(PLAZOS.keys())}")
    info = PLAZOS[body.tipo_plazo]
    inicio = datetime.strptime(body.fecha_inicio, "%Y-%m-%d").date()
    dias_r = info["dias"]
    fecha = inicio
    while dias_r > 0:
        fecha += timedelta(1)
        if fecha.weekday() < 5: dias_r -= 1
    return {"tipo_plazo": body.tipo_plazo, "norma": info["norma"],
            "dias_habiles": info["dias"], "fecha_inicio": body.fecha_inicio,
            "fecha_vence": fecha.isoformat(), "dias_quedan": (fecha-date.today()).days,
            "evento_sugerido": {"titulo": f"VENCE: {body.tipo_plazo.upper()}",
                                "fecha_inicio": fecha.isoformat(), "tipo": "vencimiento",
                                "color": "#dc2626", "caso_id": body.caso_id}}
