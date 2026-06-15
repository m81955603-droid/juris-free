"""
JURIS-FREE Bolivia — API de Biblioteca Legal
Busqueda en normativa boliviana: CPE, codigos, leyes, sentencias TCP
"""

from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import json
import os
import re
import logging
import httpx

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_KEY", ""))

# Modelo multilingue, 384 dims — mismo usado en ingestion/generar_embeddings.py
EMBED_MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"
_embed_model = None


def sb_headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }


def get_embed_model():
    """Carga el modelo de embeddings en memoria (lazy, una sola vez)."""
    global _embed_model
    if _embed_model is None:
        from sentence_transformers import SentenceTransformer
        logger.info(f"Cargando modelo de embeddings {EMBED_MODEL_NAME}...")
        _embed_model = SentenceTransformer(EMBED_MODEL_NAME)
        logger.info("Modelo de embeddings cargado OK")
    return _embed_model

# Cache en memoria del conocimiento legal
_knowledge_cache = None
NORMAS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'ingestion', 'normas_bolivia.json')


def load_knowledge():
    global _knowledge_cache
    if _knowledge_cache is None:
        try:
            # Intentar cargar desde HuggingFace primero
            hf_token = os.getenv("HF_TOKEN")
            hf_repo = os.getenv("HF_DATASET_REPO")
            if hf_token and hf_repo:
                try:
                    from huggingface_hub import hf_hub_download
                    path = hf_hub_download(
                        repo_id=hf_repo,
                        filename="normas_bolivia.json",
                        repo_type="dataset",
                        token=hf_token
                    )
                    with open(path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        _knowledge_cache = data.get('documentos', [])
                    print(f"Normas cargadas desde HuggingFace: {len(_knowledge_cache)}")
                    return _knowledge_cache
                except Exception as e:
                    print(f"No se pudo cargar desde HF, usando local: {e}")

            # Fallback: archivo local
            if os.path.exists(NORMAS_FILE):
                with open(NORMAS_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    _knowledge_cache = data.get('documentos', [])
                print(f"Normas cargadas desde archivo local: {len(_knowledge_cache)}")
            else:
                _knowledge_cache = []
        except Exception as e:
            print(f"Error cargando base de conocimiento: {e}")
            _knowledge_cache = []
    return _knowledge_cache

class SearchResult(BaseModel):
    id: str
    tipo: str
    titulo: str
    area: str
    resumen: str
    articulos_relevantes: List[dict]
    score: float


class ArticuloResult(BaseModel):
    norma_id: str
    norma_titulo: str
    numero: str
    texto: str
    area: str


@router.get("/search", response_model=List[SearchResult])
async def search_library(
    q: str = Query(..., min_length=2, description="Termino de busqueda"),
    area: Optional[str] = Query(None, description="Filtrar por area legal"),
    tipo: Optional[str] = Query(None, description="Filtrar por tipo (ley, codigo, sentencia)"),
    limit: int = Query(10, le=20)
):
    """Busqueda en la biblioteca legal boliviana."""
    docs = load_knowledge()
    query_lower = q.lower()
    query_words = set(query_lower.split())

    results = []
    for doc in docs:
        # Filtros
        if area and doc.get('area') != area:
            continue
        if tipo and doc.get('tipo') != tipo:
            continue

        # Scoring simple por relevancia
        score = 0.0
        titulo_lower = doc.get('titulo', '').lower()
        resumen_lower = doc.get('resumen', '').lower()

        # Coincidencia en titulo (mayor peso)
        for word in query_words:
            if word in titulo_lower:
                score += 3.0

        # Coincidencia en resumen
        for word in query_words:
            if word in resumen_lower:
                score += 1.0

        # Buscar en articulos
        articulos_relevantes = []
        for art in doc.get('articulos', []):
            art_texto = art.get('texto', '').lower()
            art_score = sum(1 for w in query_words if w in art_texto)
            if art_score > 0:
                score += art_score * 0.5
                articulos_relevantes.append({
                    "numero": art.get('num', ''),
                    "texto": art.get('texto', '')[:300],
                    "relevancia": art_score
                })

        if score > 0:
            # Ordenar articulos por relevancia
            articulos_relevantes.sort(key=lambda x: x['relevancia'], reverse=True)
            results.append(SearchResult(
                id=doc.get('id', ''),
                tipo=doc.get('tipo', ''),
                titulo=doc.get('titulo', ''),
                area=doc.get('area', ''),
                resumen=doc.get('resumen', '')[:400],
                articulos_relevantes=articulos_relevantes[:3],
                score=score
            ))

    # Ordenar por score
    results.sort(key=lambda x: x.score, reverse=True)
    return results[:limit]


@router.get("/normas", response_model=List[dict])
async def list_normas(
    area: Optional[str] = None,
    tipo: Optional[str] = None
):
    """Lista todas las normas disponibles."""
    docs = load_knowledge()
    result = []
    for doc in docs:
        if area and doc.get('area') != area:
            continue
        if tipo and doc.get('tipo') != tipo:
            continue
        result.append({
            "id": doc.get('id'),
            "tipo": doc.get('tipo'),
            "titulo": doc.get('titulo'),
            "area": doc.get('area'),
            "fecha": doc.get('fecha', ''),
            "total_articulos": len(doc.get('articulos', []))
        })
    return result


@router.get("/norma/{norma_id}")
async def get_norma(norma_id: str):
    """Obtiene una norma completa por ID."""
    docs = load_knowledge()
    for doc in docs:
        if doc.get('id') == norma_id:
            return doc
    return {"error": "Norma no encontrada"}


@router.get("/articulo")
async def search_articulo(
    norma: str = Query(..., description="ID de la norma"),
    numero: str = Query(..., description="Numero de articulo")
):
    """Busca un articulo especifico en una norma."""
    docs = load_knowledge()
    for doc in docs:
        if doc.get('id') == norma or norma.lower() in doc.get('titulo', '').lower():
            for art in doc.get('articulos', []):
                if art.get('num') == numero:
                    return {
                        "norma": doc.get('titulo'),
                        "articulo": numero,
                        "texto": art.get('texto'),
                        "area": doc.get('area')
                    }
    return {"error": f"Articulo {numero} no encontrado en {norma}"}


@router.get("/stats")
async def get_stats():
    """Estadisticas de la biblioteca."""
    docs = load_knowledge()
    areas = {}
    tipos = {}
    total_articulos = 0

    for doc in docs:
        area = doc.get('area', 'otro')
        tipo = doc.get('tipo', 'otro')
        areas[area] = areas.get(area, 0) + 1
        tipos[tipo] = tipos.get(tipo, 0) + 1
        total_articulos += len(doc.get('articulos', []))

    return {
        "total_normas": len(docs),
        "total_articulos_indexados": total_articulos,
        "por_area": areas,
        "por_tipo": tipos,
        "fuentes": ["CPE 2009", "Codigo Civil Ley 12760", "Codigo Penal Ley 1768",
                    "Ley 603 Familias", "CPC Ley 439", "CPP Ley 1970", "LGT", "Ley 2341"]
    }


# ─────────────────────────────────────────────────────────────
# BUSQUEDA SEMANTICA (pgvector + sentence-transformers)
# ─────────────────────────────────────────────────────────────

class SemanticResult(BaseModel):
    norma_titulo: str
    articulo: str
    texto: str
    area: Optional[str] = None
    tipo: Optional[str] = None
    similitud: float


@router.get("/search-semantic", response_model=List[SemanticResult])
async def search_semantic(
    q: str = Query(..., min_length=3, description="Consulta en lenguaje natural"),
    area: Optional[str] = Query(None, description="Filtrar por area legal"),
    limit: int = Query(8, le=20)
):
    """
    Busqueda semantica sobre articulos legales bolivianos.
    Encuentra articulos por significado, aunque no compartan palabras exactas
    con la consulta (ej: 'despido injustificado en el embarazo' -> Ley 1152 / LGT).
    """
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise HTTPException(503, "Busqueda semantica no disponible: Supabase no configurado")

    try:
        model = get_embed_model()
        embedding = model.encode(q).tolist()
    except Exception as e:
        logger.error(f"Error generando embedding: {e}")
        raise HTTPException(500, f"Error generando embedding de la consulta: {e}")

    payload = {
        "query_embedding": embedding,
        "match_threshold": 0.2,
        "match_count": limit,
        "filter_area": area,
    }

    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(
            f"{SUPABASE_URL}/rest/v1/rpc/match_legal_documents",
            json=payload,
            headers=sb_headers(),
        )

    if r.status_code != 200:
        logger.error(f"Error en match_legal_documents: {r.status_code} {r.text}")
        raise HTTPException(502, f"Error consultando Supabase: {r.text}")

    rows = r.json()
    results = []
    for row in rows:
        meta = row.get("metadata") or {}
        # metadata puede no venir en match_legal_documents (no esta en el SELECT actual);
        # usamos title como fallback para extraer norma + articulo
        title = row.get("title", "")
        norma_titulo, _, articulo_part = title.partition(" — Art. ")
        results.append(SemanticResult(
            norma_titulo=norma_titulo or title,
            articulo=articulo_part or meta.get("articulo_num", ""),
            texto=row.get("body", ""),
            area=row.get("area"),
            tipo=row.get("type"),
            similitud=round(row.get("similarity", 0.0), 4),
        ))

    return results