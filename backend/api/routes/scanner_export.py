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
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.lib import colors

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


# ═══════════════════════════════════════════════════════════
# CARNET: anverso + reverso en tamano real, listo para imprimir
# ═══════════════════════════════════════════════════════════

class CarnetPdfRequest(BaseModel):
    front_base64: str             # imagen del anverso, sin el prefijo data:
    back_base64: Optional[str] = None   # imagen del reverso (opcional)
    mime_type: str = "image/jpeg"

# Tamano estandar de carnet/tarjeta ID (ISO/IEC 7810 ID-1), igual al de
# una cedula de identidad o tarjeta de credito: 85.6 x 53.98 mm
CARD_W = 85.6 * mm
CARD_H = 53.98 * mm


def _dibujar_marcas_recorte(c: canvas.Canvas, x: float, y: float, w: float, h: float):
    """Dibuja pequenas lineas guia en las 4 esquinas para recortar con precision."""
    largo = 5 * mm
    gap = 2 * mm
    c.setLineWidth(0.4)
    c.setStrokeColor(colors.grey)

    esquinas = [
        (x, y, -1, -1), (x + w, y, 1, -1),
        (x, y + h, -1, 1), (x + w, y + h, 1, 1),
    ]
    for cx, cy, dx, dy in esquinas:
        c.line(cx + dx*gap, cy, cx + dx*(gap+largo), cy)
        c.line(cx, cy + dy*gap, cx, cy + dy*(gap+largo))


@router.post("/export-carnet-pdf")
async def export_carnet_pdf(body: CarnetPdfRequest):
    """
    Genera una hoja A4 con el anverso y reverso del carnet en su
    TAMANO REAL (85.6 x 53.98 mm, igual a una cedula fisica), con
    lineas guia para recortar. Lista para imprimir y laminar.
    """
    try:
        front_bytes = base64.b64decode(body.front_base64)
        back_bytes = base64.b64decode(body.back_base64) if body.back_base64 else None

        buffer = io.BytesIO()
        c = canvas.Canvas(buffer, pagesize=A4)
        page_w, page_h = A4

        x = (page_w - CARD_W) / 2
        y_front = page_h - 70*mm - CARD_H
        y_back = 50*mm

        # Titulo de la hoja
        c.setFont("Helvetica-Bold", 11)
        c.setFillColor(colors.HexColor("#1e293b"))
        c.drawCentredString(page_w/2, page_h - 25*mm, "Documento de Identidad — Listo para imprimir")

        # ANVERSO
        c.setFont("Helvetica", 8)
        c.setFillColor(colors.grey)
        c.drawCentredString(page_w/2, y_front + CARD_H + 5*mm, "ANVERSO")
        front_img = ImageReader(io.BytesIO(front_bytes))
        c.drawImage(front_img, x, y_front, width=CARD_W, height=CARD_H,
                    preserveAspectRatio=False, mask='auto')
        _dibujar_marcas_recorte(c, x, y_front, CARD_W, CARD_H)

        # REVERSO
        if back_bytes:
            c.drawCentredString(page_w/2, y_back + CARD_H + 5*mm, "REVERSO")
            back_img = ImageReader(io.BytesIO(back_bytes))
            c.drawImage(back_img, x, y_back, width=CARD_W, height=CARD_H,
                        preserveAspectRatio=False, mask='auto')
            _dibujar_marcas_recorte(c, x, y_back, CARD_W, CARD_H)

        # Nota al pie
        c.setFont("Helvetica", 6.5)
        c.setFillColor(colors.grey)
        c.drawCentredString(
            page_w/2, 15*mm,
            "Tamaño real de tarjeta ID (85.6 x 53.98 mm) — Recortar por las líneas guía de las esquinas"
        )

        c.showPage()
        c.save()
        buffer.seek(0)

        return Response(
            content=buffer.read(),
            media_type="application/pdf",
            headers={"Content-Disposition": 'attachment; filename="carnet_para_imprimir.pdf"'}
        )
    except Exception as e:
        logger.error(f"Error generando PDF de carnet: {e}")
        raise HTTPException(500, f"No se pudo generar el PDF del carnet: {e}")
