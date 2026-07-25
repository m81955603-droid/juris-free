"""
JURIS-FREE Bolivia — Panel de administracion
Permite al super-admin ver, aprobar, rechazar o suspender el acceso de
abogados al sistema.

Quien es super-admin se decide UNICAMENTE por la variable de entorno
SUPER_ADMIN_EMAILS (ver core/auth.py) — no existe forma de ascender a
alguien a admin desde la app. Si en el futuro quieres agregar a otra
persona con estos poderes, se hace agregando su email a esa variable
de entorno en Render, nunca desde un boton de la interfaz.

Estas rutas SI usan la Service Key (a diferencia del resto del backend),
porque el super-admin necesita ver la lista de TODOS los usuarios, algo
que RLS normal no permite. Por seguridad, cada endpoint primero confirma
que quien llama es super-admin (usando su propio token validado, ver
get_current_user) antes de usar la service key para la operacion real.
"""
import os
import logging
from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from ..core.auth import get_current_user, CurrentUser, es_email_super_admin

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")


class CrearUsuarioRequest(BaseModel):
    email: str
    password: str
    nombre: str = ""
    aprobar_de_inmediato: bool = True


def _admin_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _exigir_super_admin(user: CurrentUser):
    if not user.es_super_admin:
        raise HTTPException(403, "Solo el administrador del sistema puede realizar esta acción.")


@router.get("/usuarios")
async def listar_usuarios(user: CurrentUser = Depends(get_current_user)):
    """Lista todos los abogados registrados (solo super-admin)."""
    _exigir_super_admin(user)
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(
            f"{SUPABASE_URL}/rest/v1/usuarios_perfil?select=*&order=fecha_registro.desc",
            headers=_admin_headers()
        )
    if r.status_code != 200:
        raise HTTPException(502, f"Error consultando usuarios: {r.text}")

    usuarios = r.json()
    # Sobreescribimos cualquier columna 'rol' vieja de la base de datos:
    # lo unico que realmente importa es si el email esta en la lista
    # fija de super-admins de Render.
    for u in usuarios:
        u["rol"] = "admin" if es_email_super_admin(u.get("email")) else "abogado"
    return usuarios


@router.post("/usuarios/{usuario_id}/aprobar")
async def aprobar_usuario(usuario_id: str, user: CurrentUser = Depends(get_current_user)):
    _exigir_super_admin(user)
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
    _exigir_super_admin(user)
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


@router.post("/usuarios/crear")
async def crear_usuario(body: CrearUsuarioRequest, user: CurrentUser = Depends(get_current_user)):
    """
    Crea una cuenta de abogado directamente (sin que la persona tenga
    que auto-registrarse ni confirmar email) — util para dar de alta a
    los abogados reales, o para hacer pruebas rapidas.

    Usa la Admin API de Supabase (email_confirm=true), asi que la
    cuenta queda lista para iniciar sesion de inmediato con el
    email/password indicados.
    """
    _exigir_super_admin(user)

    if len(body.password) < 6:
        raise HTTPException(400, "La contraseña debe tener al menos 6 caracteres.")

    payload = {
        "email": body.email.strip().lower(),
        "password": body.password,
        "email_confirm": True,
        "user_metadata": {"full_name": body.nombre},
    }
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(f"{SUPABASE_URL}/auth/v1/admin/users", json=payload, headers=headers)

        if r.status_code not in (200, 201):
            try:
                cuerpo_error = r.json()
                detalle = cuerpo_error.get("msg") or cuerpo_error.get("message") or r.text
            except Exception:
                detalle = r.text
            if "already been registered" in detalle or "already registered" in detalle:
                raise HTTPException(400, "Ya existe una cuenta con ese email.")
            raise HTTPException(502, f"Error creando el usuario: {detalle}")

        nuevo_usuario = r.json()
        nuevo_id = nuevo_usuario.get("id")

        # El trigger de la base de datos ya creo la fila en usuarios_perfil
        # (estado='pendiente') apenas se creo el auth.users. Si se pidio
        # aprobar de inmediato, la actualizamos ahora.
        if body.aprobar_de_inmediato and nuevo_id:
            await client.patch(
                f"{SUPABASE_URL}/rest/v1/usuarios_perfil?id=eq.{nuevo_id}",
                json={
                    "estado": "aprobado",
                    "fecha_aprobacion": datetime.now(timezone.utc).isoformat(),
                    "aprobado_por": user.user_id,
                },
                headers=_admin_headers()
            )

    return {"ok": True, "id": nuevo_id, "email": body.email}


@router.get("/mi-estado")
async def mi_estado(user: CurrentUser = Depends(get_current_user)):
    """El propio abogado consulta su estado de aprobacion (para la pantalla de espera)."""
    return {
        "rol": "admin" if user.es_super_admin else "abogado",
        "estado": user.estado,
        "en_prueba": user.en_prueba,
        "minutos_restantes": user.minutos_restantes,
    }
