"""
JURIS-FREE Bolivia — Lectura de API keys propias por abogado.

Cada abogado puede configurar en Ajustes sus propias claves gratuitas
de los proveedores de IA. Este modulo las consulta (respetando RLS,
usando el propio token del abogado) para que la cascada de IA en
llm.py y ocr.py las use en vez de (o antes que) las claves compartidas
del sistema.

Si el abogado no configuro ninguna clave propia, se devuelve un dict
vacio, y el llamador debe usar normalmente las claves del sistema
(variables de entorno) como respaldo.
"""
import os
import logging
import httpx

from .auth import CurrentUser, sb_user_headers

logger = logging.getLogger(__name__)

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")

# Mapea nombre de proveedor (usado en llm.py/ocr.py) -> columna en la tabla
PROVIDER_COLUMNS = {
    "gemini":     "gemini_api_key",
    "groq":       "groq_api_key",
    "cerebras":   "cerebras_api_key",
    "openrouter": "openrouter_api_key",
    "sambanova":  "sambanova_api_key",
    "mistral":    "mistral_api_key",
}


async def obtener_claves_usuario(user: CurrentUser) -> dict:
    """
    Devuelve {"gemini": "clave...", "groq": "clave..."} solo con los
    proveedores que el abogado configuro. Nunca lanza excepcion: si algo
    falla (tabla no existe todavia, red, etc.) devuelve {} en silencio,
    para que el sistema siga funcionando con las claves compartidas.
    """
    if not SUPABASE_URL:
        return {}
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            r = await client.get(
                f"{SUPABASE_URL}/rest/v1/usuario_api_keys?user_id=eq.{user.user_id}&select=*",
                headers=sb_user_headers(user)
            )
        if r.status_code != 200:
            return {}
        filas = r.json()
        if not filas:
            return {}
        fila = filas[0]
        return {
            proveedor: fila[columna]
            for proveedor, columna in PROVIDER_COLUMNS.items()
            if fila.get(columna)
        }
    except Exception as e:
        logger.warning(f"No se pudieron obtener las API keys propias del usuario: {e}")
        return {}
