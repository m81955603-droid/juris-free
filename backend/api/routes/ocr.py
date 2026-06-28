import httpx, os, base64, logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)
router = APIRouter()

class OcrRequest(BaseModel):
    image_base64: str
    mode: str = "document"  # "document" o "carnet"
    mime_type: str = "image/jpeg"

class OcrResponse(BaseModel):
    text: str
    mode: str

@router.post("/scan", response_model=OcrResponse)
async def scan_document(req: OcrRequest):
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY no configurada")

    if req.mode == "carnet":
        prompt = """Extrae los datos de esta carnet de identidad boliviana.
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
    else:
        prompt = """Eres un asistente OCR especializado en documentos legales bolivianos.
Extrae TODO el texto de este documento con maxima precision.
Mantén el formato original: parrafos, titulos, numeracion.
Si hay sellos o firmas, indicalos como [SELLO] o [FIRMA].
Responde SOLO con el texto extraido, sin comentarios adicionales."""

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    body = {
        "contents": [{
            "parts": [
                {"text": prompt},
                {"inline_data": {"mime_type": req.mime_type, "data": req.image_base64}}
            ]
        }]
    }

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(url, json=body)
            resp.raise_for_status()
            data = resp.json()
            text = data["candidates"][0]["content"]["parts"][0]["text"]
            return OcrResponse(text=text, mode=req.mode)
    except Exception as e:
        logger.error(f"OCR error: {e}")
        raise HTTPException(status_code=500, detail=f"Error al procesar imagen: {str(e)}")
