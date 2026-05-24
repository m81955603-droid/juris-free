"""
JURIS-FREE Bolivia — Servidor de Muestras Word
Sirve 5,737 archivos Word desde el filesystem local
"""

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, List
import os
import json

router = APIRouter()

MUESTRAS_BASE = os.environ.get('MUESTRAS_PATH', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'muestras'))

# Cache del indice en memoria
_index_cache = None

# Mapeo de carpetas a categorias
CARPETA_CATEGORIA = {
    "1.- MATERIAL ANTIGUO":                                  "Material Antiguo",
    "2.- SUPER MALETA PAR ABOGADOS":                        "Super Maleta",
    "3.- DERECHO ACTUAL 1":                                  "Derecho Actual 1",
    "4.- DERECHO ACTUAL 2":                                  "Derecho Actual 2",
    "5.- DERECHO ACTUAL 3":                                  "Derecho Actual 3",
    "6.- CODIGO PRECESAL CIVIL CONCORDADO":                  "Codigo Procesal Civil",
    "12.- PROCEDIMIENTO_ FAMILIAR, NIÑA NIÑO ADOLECENTE":   "Procedimiento Familiar"
}

CARPETA_ICONO = {
    "1.- MATERIAL ANTIGUO":          "📁",
    "2.- SUPER MALETA PAR ABOGADOS": "💼",
    "3.- DERECHO ACTUAL 1":          "📚",
    "4.- DERECHO ACTUAL 2":          "📚",
    "5.- DERECHO ACTUAL 3":          "📚",
    "6.- CODIGO PRECESAL CIVIL CONCORDADO": "⚖",
    "12.- PROCEDIMIENTO_ FAMILIAR, NIÑA NIÑO ADOLECENTE": "👨‍👩‍👧"
}


class Muestra(BaseModel):
    id: str
    nombre: str
    carpeta: str
    subcarpeta: str
    categoria: str
    icono: str
    ruta_relativa: str
    tamanio: int


class MuestraIndex(BaseModel):
    total: int
    carpetas: List[dict]


def build_index() -> list:
    """Construye el indice de todos los archivos Word."""
    global _index_cache
    if _index_cache is not None:
        return _index_cache

    index = []
    if not os.path.exists(MUESTRAS_BASE):
        return index

    for carpeta_principal in sorted(os.listdir(MUESTRAS_BASE)):
        carpeta_path = os.path.join(MUESTRAS_BASE, carpeta_principal)
        if not os.path.isdir(carpeta_path):
            continue

        categoria  = CARPETA_CATEGORIA.get(carpeta_principal, carpeta_principal)
        icono      = CARPETA_ICONO.get(carpeta_principal, "📄")

        # Recorrer recursivamente
        for root, dirs, files in os.walk(carpeta_path):
            dirs.sort()
            for filename in sorted(files):
                if not filename.lower().endswith(('.docx', '.doc')):
                    continue

                full_path  = os.path.join(root, filename)
                rel_path   = os.path.relpath(full_path, MUESTRAS_BASE)
                subcarpeta = os.path.relpath(root, carpeta_path)
                if subcarpeta == '.':
                    subcarpeta = ''

                try:
                    tamanio = os.path.getsize(full_path)
                except:
                    tamanio = 0

                # ID unico basado en ruta
                doc_id = rel_path.replace('\\', '/').replace(' ', '_')

                index.append({
                    "id":             doc_id,
                    "nombre":         os.path.splitext(filename)[0],
                    "carpeta":        carpeta_principal,
                    "subcarpeta":     subcarpeta,
                    "categoria":      categoria,
                    "icono":          icono,
                    "ruta_relativa":  rel_path.replace('\\', '/'),
                    "tamanio":        tamanio
                })

    _index_cache = index
    return index


@router.get("/index")
async def get_index():
    """Indice completo con estadisticas por carpeta."""
    index = build_index()

    # Agrupar por carpeta
    carpetas = {}
    for doc in index:
        c = doc["carpeta"]
        if c not in carpetas:
            carpetas[c] = {
                "nombre":    c,
                "categoria": doc["categoria"],
                "icono":     doc["icono"],
                "total":     0,
                "subcarpetas": {}
            }
        carpetas[c]["total"] += 1

        sub = doc["subcarpeta"]
        if sub:
            if sub not in carpetas[c]["subcarpetas"]:
                carpetas[c]["subcarpetas"][sub] = 0
            carpetas[c]["subcarpetas"][sub] += 1

    return {
        "total":    len(index),
        "carpetas": list(carpetas.values())
    }


@router.get("/search")
async def search_muestras(
    q:       str            = Query("", description="Termino de busqueda"),
    carpeta: Optional[str]  = Query(None, description="Filtrar por carpeta"),
    page:    int            = Query(1, ge=1),
    limit:   int            = Query(50, le=200)
):
    """Busqueda paginada en el indice de muestras."""
    index = build_index()
    q_lower = q.lower().strip()

    # Filtrar
    results = []
    for doc in index:
        if carpeta and doc["carpeta"] != carpeta:
            continue
        if q_lower:
            if q_lower not in doc["nombre"].lower() and \
               q_lower not in doc["subcarpeta"].lower():
                continue
        results.append(doc)

    total = len(results)
    start = (page - 1) * limit
    end   = start + limit

    return {
        "total":   total,
        "page":    page,
        "limit":   limit,
        "pages":   (total + limit - 1) // limit,
        "results": results[start:end]
    }


@router.get("/download")
async def download_muestra(ruta: str = Query(..., description="Ruta relativa del archivo")):
    """Descarga un archivo Word por su ruta relativa."""
    # Seguridad: no permitir path traversal
    ruta_limpia = ruta.replace('..', '').replace('//', '/')
    full_path   = os.path.join(MUESTRAS_BASE, ruta_limpia.replace('/', os.sep))

    if not os.path.exists(full_path):
        raise HTTPException(404, f"Archivo no encontrado: {ruta}")

    if not full_path.startswith(MUESTRAS_BASE):
        raise HTTPException(403, "Acceso denegado")

    filename = os.path.basename(full_path)
    return FileResponse(
        path        = full_path,
        filename    = filename,
        media_type  = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )


@router.get("/stats")
async def get_stats():
    """Estadisticas del repositorio."""
    index = build_index()
    total_size = sum(d["tamanio"] for d in index)
    return {
        "total_archivos": len(index),
        "total_mb":       round(total_size / (1024 * 1024), 1),
        "carpetas":       len(set(d["carpeta"] for d in index))
    }