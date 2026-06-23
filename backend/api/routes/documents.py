"""
JURIS-FREE Bolivia — API de Documentos
Extracción de texto + Gestión de plantillas personales con análisis de estilo IA
"""
import io
import logging
import chardet
import os
import httpx
import json
from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")
GEMINI_KEY   = os.getenv("GEMINI_API_KEY", "")

def sb_headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


# ─────────────────────────────────────────────────────────────
# EXTRACCION DE TEXTO (existente)
# ─────────────────────────────────────────────────────────────

@router.post("/extract-text")
async def extract_text(file: UploadFile = File(...)):
    """Extrae texto de PDF, DOCX, DOC o TXT"""
    filename = file.filename or ""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    content = await file.read()

    try:
        if ext == "pdf":
            text = extract_pdf(content)
        elif ext == "docx":
            text = extract_docx(content)
        elif ext == "doc":
            text = extract_doc(content)
        elif ext == "txt":
            detected = chardet.detect(content)
            encoding = detected.get("encoding") or "utf-8"
            text = content.decode(encoding, errors="replace")
        else:
            raise HTTPException(400, f"Formato .{ext} no soportado")

        if not text.strip():
            raise HTTPException(422, "No se pudo extraer texto del documento")

        return {"text": text, "chars": len(text), "filename": filename}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error extrayendo texto de {filename}: {e}")
        raise HTTPException(500, f"Error procesando archivo: {str(e)}")


# ─────────────────────────────────────────────────────────────
# PLANTILLAS PERSONALES
# ─────────────────────────────────────────────────────────────

class PlantillaCreate(BaseModel):
    nombre: str
    tipo_documento: Optional[str] = "general"
    texto_original: str


@router.get("/plantillas")
async def get_plantillas():
    """Lista todas las plantillas personales del usuario."""
    url = f"{SUPABASE_URL}/rest/v1/plantillas_usuario?select=*&order=created_at.desc"
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.get(url, headers=sb_headers())
    if r.status_code == 404:
        return []  # Tabla no existe aún
    if r.status_code != 200:
        logger.error(f"Error cargando plantillas: {r.text}")
        return []
    return r.json()


@router.post("/plantillas/analizar")
async def analizar_plantilla(file: UploadFile = File(...), nombre: str = "Mi plantilla"):
    """
    Sube un documento Word/PDF, extrae el texto y usa IA para crear
    una ficha de estilo: tono, estructura, variables y preferencias de formato.
    """
    filename = file.filename or ""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    content = await file.read()

    # Extraer texto
    try:
        if ext == "pdf":
            texto = extract_pdf(content)
        elif ext in ("docx", "doc"):
            texto = extract_docx(content) if ext == "docx" else extract_doc(content)
        elif ext == "txt":
            detected = chardet.detect(content)
            encoding = detected.get("encoding") or "utf-8"
            texto = content.decode(encoding, errors="replace")
        else:
            raise HTTPException(400, f"Formato .{ext} no soportado")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Error procesando archivo: {e}")

    if not texto.strip():
        raise HTTPException(422, "No se pudo extraer texto del documento")

    # Analizar estilo con Gemini
    if not GEMINI_KEY:
        raise HTTPException(503, "GEMINI_API_KEY no configurada")

    prompt = f"""Analiza este documento legal boliviano y extrae su perfil de estilo de redacción.

DOCUMENTO:
{texto[:8000]}

Responde SOLO en JSON con esta estructura exacta:
{{
  "tono": "formal|conciliador|agresivo|técnico|notarial",
  "estructura_preferida": "descripción de cómo organiza el documento",
  "conectores_frecuentes": ["lista", "de", "conectores", "que", "usa"],
  "nivel_tecnico": "alto|medio|básico",
  "preferencias_formato": {{
    "usa_negritas": true,
    "usa_numeracion": true,
    "usa_sangria_francesa": false,
    "citas_al_pie": false
  }},
  "variables_detectadas": ["{{cliente}}", "{{demandado}}", "{{fecha}}"],
  "tipo_documento": "contrato|demanda|memorial|poder|denuncia|otro",
  "system_prompt_personalizado": "Instrucción completa de 2-3 oraciones para que la IA escriba en este estilo exacto",
  "resumen_estilo": "Una sola oración describiendo el estilo único de este abogado"
}}

Sin texto adicional fuera del JSON."""

    gemini_url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={GEMINI_KEY}"
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1500}
    }

    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(gemini_url, json=payload)

    if r.status_code != 200:
        raise HTTPException(502, f"Error Gemini: {r.text}")

    raw = r.json()["candidates"][0]["content"]["parts"][0]["text"]
    raw = raw.replace("```json", "").replace("```", "").strip()

    try:
        ficha = json.loads(raw)
    except json.JSONDecodeError:
        ficha = {
            "tono": "formal",
            "resumen_estilo": "Estilo formal boliviano estándar",
            "system_prompt_personalizado": "Redacta en estilo jurídico boliviano formal.",
            "variables_detectadas": [],
            "tipo_documento": "general"
        }

    # Guardar en Supabase
    plantilla_data = {
        "nombre": nombre,
        "tipo_documento": ficha.get("tipo_documento", "general"),
        "texto_original": texto[:5000],
        "ficha_estilo": json.dumps(ficha, ensure_ascii=False),
        "tono": ficha.get("tono", "formal"),
        "resumen_estilo": ficha.get("resumen_estilo", ""),
        "system_prompt": ficha.get("system_prompt_personalizado", ""),
        "variables": json.dumps(ficha.get("variables_detectadas", []))
    }

    async with httpx.AsyncClient(timeout=20) as client:
        r_save = await client.post(
            f"{SUPABASE_URL}/rest/v1/plantillas_usuario",
            json=plantilla_data,
            headers=sb_headers()
        )

    saved = r_save.json() if r_save.status_code in (200, 201) else None
    saved_id = saved[0]["id"] if isinstance(saved, list) and saved else None

    return {
        "id": saved_id,
        "nombre": nombre,
        "ficha": ficha,
        "chars_analizados": len(texto),
        "guardada": saved_id is not None
    }


@router.delete("/plantillas/{id}")
async def delete_plantilla(id: str):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.delete(
            f"{SUPABASE_URL}/rest/v1/plantillas_usuario?id=eq.{id}",
            headers={**sb_headers(), "Prefer": "return=minimal"}
        )
    if r.status_code not in (200, 204):
        raise HTTPException(502, f"Error eliminando: {r.text}")
    return {"ok": True}


# ─────────────────────────────────────────────────────────────
# HELPERS DE EXTRACCION (existentes)
# ─────────────────────────────────────────────────────────────

def extract_pdf(content: bytes) -> str:
    import fitz
    doc = fitz.open(stream=content, filetype="pdf")
    text = ""
    for page in doc:
        text += page.get_text() + "\n\n"
    doc.close()
    return text.strip()


def extract_docx(content: bytes) -> str:
    from docx import Document
    doc = Document(io.BytesIO(content))
    paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
    return "\n\n".join(paragraphs)


def extract_doc(content: bytes) -> str:
    for encoding in ["latin-1", "cp1252", "utf-8"]:
        try:
            text = content.decode(encoding, errors="ignore")
            clean = "".join(c for c in text if c.isprintable() or c in "\n\r\t")
            if len(clean.strip()) > 100:
                return clean.strip()
        except Exception:
            continue
    raise HTTPException(422, "No se pudo leer el archivo .doc. Por favor conviértelo a .docx o .pdf")
