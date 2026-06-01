import io
import logging
import chardet
from fastapi import APIRouter, UploadFile, File, HTTPException

logger = logging.getLogger(__name__)
router = APIRouter()

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


def extract_pdf(content: bytes) -> str:
    import fitz  # PyMuPDF
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
    # Intentar leer .doc como texto con diferentes encodings
    for encoding in ["latin-1", "cp1252", "utf-8"]:
        try:
            text = content.decode(encoding, errors="ignore")
            # Filtrar caracteres no imprimibles
            clean = "".join(c for c in text if c.isprintable() or c in "\n\r\t")
            # Buscar texto legible (al menos 100 chars)
            if len(clean.strip()) > 100:
                return clean.strip()
        except Exception:
            continue
    raise HTTPException(422, "No se pudo leer el archivo .doc. Por favor conviértelo a .docx o .pdf")