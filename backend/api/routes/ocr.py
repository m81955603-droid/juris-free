"""
JURIS-FREE Bolivia — Scanner OCR con cascada de 3 proveedores
Si un proveedor falla (cuota agotada, error, modelo caido), cae
automaticamente al siguiente. El usuario nunca deberia ver un error
salvo que los 3 fallen al mismo tiempo (muy improbable).

Orden:
  1. Gemini 2.5 Flash-Lite   -> mejor cuota diaria gratis, rapido
  2. Mistral OCR             -> especializado en documentos, cuota enorme
  3. Groq Llama 4 Scout      -> respaldo final, tambien gratis
"""
import httpx, os, logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()

GEMINI_KEY  = os.environ.get("GEMINI_API_KEY", "")
MISTRAL_KEY = os.environ.get("MISTRAL_API_KEY", "")
GROQ_KEY    = os.environ.get("GROQ_API_KEY", "")


class OcrRequest(BaseModel):
    image_base64: str
    mode: str = "document"  # "document" o "carnet"
    mime_type: str = "image/jpeg"


class OcrResponse(BaseModel):
    text: str
    mode: str
    proveedor: str = ""  # informativo: cual proveedor respondio


def _prompt_para(mode: str) -> str:
    if mode == "carnet":
        return """Extrae los datos de esta carnet de identidad boliviana.
Responde UNICAMENTE en JSON con este formato exacto:
{
  "nombre_completo": "",
  "numero_ci": "",
  "fecha_nacimiento": "",
  "lugar_nacimiento": "",
  "fecha_expiracion": "",
  "estado_civil": "",
  "observaciones": ""
}
Si un campo no se ve claramente, dejarlo vacio."""
    return """Eres un asistente OCR especializado en documentos legales bolivianos.
Extrae TODO el texto de este documento con maxima precision.
Mantén el formato original: parrafos, titulos, numeracion.
Si hay sellos o firmas, indicalos como [SELLO] o [FIRMA].
Responde SOLO con el texto extraido, sin comentarios adicionales."""


async def _intentar_gemini(req: OcrRequest) -> str:
    if not GEMINI_KEY:
        raise RuntimeError("GEMINI_API_KEY no configurada")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key={GEMINI_KEY}"
    body = {
        "contents": [{
            "parts": [
                {"text": _prompt_para(req.mode)},
                {"inline_data": {"mime_type": req.mime_type, "data": req.image_base64}}
            ]
        }]
    }
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(url, json=body)
        resp.raise_for_status()
        data = resp.json()
        return data["candidates"][0]["content"]["parts"][0]["text"]


async def _intentar_mistral(req: OcrRequest) -> str:
    if not MISTRAL_KEY:
        raise RuntimeError("MISTRAL_API_KEY no configurada")

    data_url = f"data:{req.mime_type};base64,{req.image_base64}"

    if req.mode == "carnet":
        url = "https://api.mistral.ai/v1/chat/completions"
        body = {
            "model": "pixtral-12b-2409",
            "messages": [{
                "role": "user",
                "content": [
                    {"type": "text", "text": _prompt_para(req.mode)},
                    {"type": "image_url", "image_url": data_url}
                ]
            }]
        }
        headers = {"Authorization": f"Bearer {MISTRAL_KEY}", "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(url, json=body, headers=headers)
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"]

    url = "https://api.mistral.ai/v1/ocr"
    body = {
        "model": "mistral-ocr-latest",
        "document": {"type": "image_url", "image_url": data_url}
    }
    headers = {"Authorization": f"Bearer {MISTRAL_KEY}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(url, json=body, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        paginas = data.get("pages", [])
        return "\n\n".join(p.get("markdown", "") for p in paginas) or "(sin texto detectado)"


async def _intentar_groq(req: OcrRequest) -> str:
    if not GROQ_KEY:
        raise RuntimeError("GROQ_API_KEY no configurada")
    url = "https://api.groq.com/openai/v1/chat/completions"
    data_url = f"data:{req.mime_type};base64,{req.image_base64}"
    body = {
        "model": "meta-llama/llama-4-scout-17b-16e-instruct",
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": _prompt_para(req.mode)},
                {"type": "image_url", "image_url": {"url": data_url}}
            ]
        }]
    }
    headers = {"Authorization": f"Bearer {GROQ_KEY}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(url, json=body, headers=headers)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


@router.post("/scan", response_model=OcrResponse)
async def scan_document(req: OcrRequest):
    proveedores = [
        ("Gemini 2.5 Flash-Lite", _intentar_gemini),
        ("Mistral OCR",           _intentar_mistral),
        ("Groq Llama 4 Scout",    _intentar_groq),
    ]

    errores = []
    for nombre, fn in proveedores:
        try:
            texto = await fn(req)
            if texto and texto.strip():
                logger.info(f"OCR resuelto por: {nombre}")
                return OcrResponse(text=texto, mode=req.mode, proveedor=nombre)
        except Exception as e:
            logger.warning(f"OCR fallo con {nombre}: {e}")
            errores.append(f"{nombre}: {e}")
            continue

    logger.error(f"OCR fallo con los 3 proveedores: {' | '.join(errores)}")
    raise HTTPException(
        status_code=503,
        detail="No se pudo procesar la imagen con ningun proveedor disponible. Intenta de nuevo en unos minutos."
    )