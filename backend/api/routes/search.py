"""
JURIS-FREE Bolivia — Búsqueda Global
Busca en: casos, notas de casos, clientes, biblioteca (semántica)
"""
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import os, httpx, logging

logger = logging.getLogger(__name__)
router = APIRouter()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")
GEMINI_KEY   = os.getenv("GEMINI_API_KEY", "")

GEMINI_EMBED_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-embedding-2:embedContent?key="
)

def sb_headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }


class SearchHit(BaseModel):
    tipo:      str   # 'caso' | 'nota' | 'cliente' | 'norma'
    id:        str
    titulo:    str
    subtitulo: Optional[str] = None
    snippet:   Optional[str] = None
    url:       str
    score:     float = 1.0


@router.get("/search", response_model=List[SearchHit])
async def global_search(
    q: str = Query(..., min_length=2),
    limit: int = Query(12, le=30)
):
    """
    Búsqueda global sobre casos, notas, clientes y biblioteca legal.
    Combina full-text (Supabase ilike) + semántica (pgvector) en paralelo.
    """
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise HTTPException(503, "Supabase no configurado")

    results: List[SearchHit] = []
    q_lower = q.lower()

    async with httpx.AsyncClient(timeout=20) as client:

        # ── Casos (full-text) ──────────────────────────────────
        r_casos = await client.get(
            f"{SUPABASE_URL}/rest/v1/casos"
            f"?or=(titulo.ilike.*{q_lower}*,cliente.ilike.*{q_lower}*,descripcion.ilike.*{q_lower}*)"
            f"&select=id,titulo,cliente,tipo,estado,numero_expediente"
            f"&order=updated_at.desc&limit=5",
            headers=sb_headers()
        )
        if r_casos.status_code == 200:
            for c in r_casos.json():
                results.append(SearchHit(
                    tipo="caso",
                    id=c["id"],
                    titulo=c["titulo"],
                    subtitulo=f"{c['tipo'].capitalize()} · {c['cliente']}",
                    snippet=c.get("numero_expediente") or c.get("estado", ""),
                    url=f"/cases",
                    score=1.0
                ))

        # ── Notas de casos (full-text) ─────────────────────────
        r_notas = await client.get(
            f"{SUPABASE_URL}/rest/v1/caso_notas"
            f"?contenido=ilike.*{q_lower}*"
            f"&select=id,contenido,caso_id,tipo,created_at"
            f"&order=created_at.desc&limit=4",
            headers=sb_headers()
        )
        if r_notas.status_code == 200:
            for n in r_notas.json():
                snippet = n["contenido"][:120] + "..." if len(n["contenido"]) > 120 else n["contenido"]
                results.append(SearchHit(
                    tipo="nota",
                    id=n["id"],
                    titulo=f"Nota: {snippet[:50]}",
                    subtitulo=n.get("tipo", "nota").capitalize(),
                    snippet=snippet,
                    url=f"/cases",
                    score=0.9
                ))

        # ── Clientes (full-text) ───────────────────────────────
        r_clientes = await client.get(
            f"{SUPABASE_URL}/rest/v1/clientes"
            f"?or=(nombre.ilike.*{q_lower}*,email.ilike.*{q_lower}*,ci_nit.ilike.*{q_lower}*)"
            f"&select=id,nombre,telefono,email,tipo,ciudad"
            f"&limit=4",
            headers=sb_headers()
        )
        if r_clientes.status_code == 200:
            for cl in r_clientes.json():
                results.append(SearchHit(
                    tipo="cliente",
                    id=cl["id"],
                    titulo=cl["nombre"],
                    subtitulo=f"{'Empresa' if cl.get('tipo') == 'empresa' else 'Persona'} · {cl.get('ciudad', '')}",
                    snippet=cl.get("email") or cl.get("telefono") or "",
                    url=f"/clients",
                    score=1.0
                ))

        # ── Biblioteca semántica (pgvector) ───────────────────
        if GEMINI_KEY:
            try:
                embed_payload = {
                    "model": "models/gemini-embedding-2",
                    "content": {"parts": [{"text": q}]},
                    "taskType": "RETRIEVAL_QUERY",
                }
                r_emb = await client.post(
                    GEMINI_EMBED_URL + GEMINI_KEY,
                    json=embed_payload, timeout=15
                )
                if r_emb.status_code == 200:
                    embedding = r_emb.json()["embedding"]["values"][:1536]
                    rpc_payload = {
                        "query_embedding": embedding,
                        "match_threshold": 0.4,
                        "match_count": 4,
                        "filter_area": None,
                    }
                    r_lib = await client.post(
                        f"{SUPABASE_URL}/rest/v1/rpc/match_legal_documents",
                        json=rpc_payload, headers=sb_headers()
                    )
                    if r_lib.status_code == 200:
                        for doc in r_lib.json():
                            title = doc.get("title", "")
                            norma, _, art = title.partition(" — Art. ")
                            results.append(SearchHit(
                                tipo="norma",
                                id=doc.get("id", ""),
                                titulo=f"Art. {art} — {norma}" if art else title,
                                subtitulo=f"Biblioteca · {doc.get('area', '')}",
                                snippet=doc.get("body", "")[:120] + "...",
                                url="/library",
                                score=round(doc.get("similarity", 0.5), 3)
                            ))
            except Exception as e:
                logger.warning(f"Error búsqueda semántica en global search: {e}")

    # Ordenar por score y limitar
    results.sort(key=lambda x: x.score, reverse=True)
    return results[:limit]
