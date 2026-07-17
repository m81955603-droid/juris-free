"""
JURIS-FREE Bolivia — Exportacion de documentos escaneados (multi-pagina)
Combina varias fotos escaneadas en un PDF real, o el texto extraido
de varias paginas en un documento Word editable.

No requiere autenticacion: no toca la base de datos, solo transforma
los datos que el navegador ya tiene (imagenes/texto de la sesion actual).
"""
import base64
import io
import logging
from typing import List, Optional

import fitz  # PyMuPDF
from docx import Document
from docx.shared import Pt, Inches
from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()


class Pagina(BaseModel):
    image_base64: str            # imagen JPEG/PNG en base64 (sin el prefijo data:)
    mime_type: str = "image/jpeg"
    texto: Optional[str] = ""    # texto OCR de esta pagina (para exportar a Word)


class ExportRequest(BaseModel):
    paginas: List[Pagina]
    titulo: Optional[str] = "Documento escaneado"


@router.post("/export-pdf")
async def export_pdf(body: ExportRequest):
    """Combina todas las paginas (imagenes) en un solo PDF, una imagen por hoja."""
    if not body.paginas:
        raise HTTPException(400, "No hay paginas para exportar")

    try:
        pdf = fitz.open()
        for pagina in body.paginas:
            img_bytes = base64.b64decode(pagina.image_base64)
            img_doc = fitz.open(stream=img_bytes, filetype="jpg" if "jpeg" in pagina.mime_type or "jpg" in pagina.mime_type else "png")
            rect = img_doc[0].rect
            pdf_page = pdf.new_page(width=rect.width, height=rect.height)
            pdf_page.insert_image(rect, stream=img_bytes)
            img_doc.close()

        buffer = io.BytesIO()
        pdf.save(buffer)
        pdf.close()
        buffer.seek(0)

        return Response(
            content=buffer.read(),
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{body.titulo}.pdf"'}
        )
    except Exception as e:
        logger.error(f"Error exportando PDF: {e}")
        raise HTTPException(500, f"No se pudo generar el PDF: {e}")


@router.post("/export-word")
async def export_word(body: ExportRequest):
    """Combina el texto OCR de todas las paginas en un documento Word editable."""
    if not body.paginas:
        raise HTTPException(400, "No hay paginas para exportar")

    try:
        doc = Document()
        doc.add_heading(body.titulo, level=1)

        for i, pagina in enumerate(body.paginas, start=1):
            if len(body.paginas) > 1:
                doc.add_heading(f"Pagina {i}", level=2)
            texto = (pagina.texto or "").strip() or "(sin texto detectado en esta pagina)"
            for parrafo in texto.split("\n"):
                if parrafo.strip():
                    p = doc.add_paragraph(parrafo)
                    p.style.font.size = Pt(11)
            if i < len(body.paginas):
                doc.add_page_break()

        buffer = io.BytesIO()
        doc.save(buffer)
        buffer.seek(0)

        return Response(
            content=buffer.read(),
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            headers={"Content-Disposition": f'attachment; filename="{body.titulo}.docx"'}
        )
    except Exception as e:
        logger.error(f"Error exportando Word: {e}")
        raise HTTPException(500, f"No se pudo generar el documento Word: {e}")
