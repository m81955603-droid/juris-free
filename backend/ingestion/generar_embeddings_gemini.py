"""
JURIS-FREE Bolivia — Generador de Embeddings con Gemini API
Lee normas_bolivia.json, genera embeddings con Gemini text-embedding-004
(768 dims, gratis) y los sube a legal_documents en Supabase via REST.

Uso:
    cd C:\proyectos\juris-free\backend
    python ingestion\generar_embeddings_gemini.py

Requiere en backend/.env:
    SUPABASE_URL
    SUPABASE_SERVICE_KEY
    GEMINI_API_KEY
"""

import json
import os
import sys
import time

import httpx
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")
GEMINI_KEY   = os.getenv("GEMINI_API_KEY", "")
NORMAS_FILE  = os.path.join(BASE_DIR, "normas_bolivia.json")

GEMINI_EMBED_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-embedding-2:embedContent?key=" + GEMINI_KEY
)

TIPO_MAP = {
    "codigo": "ley",
    "constitucion": "constitucion",
    "ley": "ley",
    "decreto": "decreto",
    "sentencia": "sentencia",
    "resolucion": "resolucion",
}


def sb_headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }


def gemini_embed(client: httpx.Client, texto: str) -> list[float]:
    """Llama a Gemini text-embedding-004 y devuelve vector de 768 dims."""
    payload = {
        "model": "models/gemini-embedding-001",
        "content": {"parts": [{"text": texto}]},
        "taskType": "RETRIEVAL_DOCUMENT",
    }
    for intento in range(3):
        r = client.post(GEMINI_EMBED_URL, json=payload, timeout=30)
        if r.status_code == 200:
            return r.json()["embedding"]["values"]
        if r.status_code == 429:
            wait = 10 * (intento + 1)
            print(f"  Rate limit Gemini, esperando {wait}s...")
            time.sleep(wait)
        else:
            print(f"  Error Gemini {r.status_code}: {r.text}")
            raise RuntimeError(f"Gemini error: {r.status_code}")
    raise RuntimeError("Gemini rate limit agotado tras 3 intentos")


def main():
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("ERROR: Faltan SUPABASE_URL / SUPABASE_SERVICE_KEY en .env")
        sys.exit(1)
    if not GEMINI_KEY:
        print("ERROR: Falta GEMINI_API_KEY en .env")
        sys.exit(1)

    print(f"Leyendo {NORMAS_FILE}...")
    with open(NORMAS_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    docs = data.get("documentos", [])
    print(f"Normas encontradas: {len(docs)}")

    items = []
    for norma in docs:
        norma_id    = norma.get("id", "")
        titulo      = norma.get("titulo", "")
        area        = norma.get("area", "")
        tipo        = TIPO_MAP.get(norma.get("tipo", "ley"), "ley")
        fecha       = norma.get("fecha")

        for art in norma.get("articulos", []):
            numero = art.get("num", "")
            texto  = art.get("texto", "")
            if not texto.strip():
                continue
            items.append({
                "title":          f"{titulo} — Art. {numero}",
                "body":           texto,
                "type":           tipo,
                "area":           area,
                "published_date": fecha,
                "jurisdiction":   "nacional",
                "source_url":     None,
                "metadata": {
                    "norma_id":     norma_id,
                    "norma_titulo": titulo,
                    "articulo_num": numero,
                },
                "_embed_text": f"{titulo}. Articulo {numero}. {texto}",
            })

    print(f"Total articulos a procesar: {len(items)}")

    # Limpiar tabla
    print("Limpiando legal_documents...")
    with httpx.Client(timeout=60) as client:
        r = client.delete(
            f"{SUPABASE_URL}/rest/v1/legal_documents"
            "?type=in.(ley,decreto,sentencia,resolucion,constitucion)",
            headers=sb_headers(),
        )
        if r.status_code not in (200, 204):
            print(f"  Aviso al limpiar: {r.status_code} {r.text}")

    # Generar embeddings con Gemini e insertar de a 1 (API no tiene batch)
    print("Generando embeddings con Gemini text-embedding-004 e insertando...")
    print("(Puede tardar ~2 min para 98 articulos por rate limits)\n")

    with httpx.Client(timeout=60) as client:
        for i, item in enumerate(items):
            embed_text = item.pop("_embed_text")

            # Generar embedding
            embedding = gemini_embed(client, embed_text)
            embedding = embedding[:1536]
            item["embedding"] = embedding

            # Insertar en Supabase
            r = client.post(
                f"{SUPABASE_URL}/rest/v1/legal_documents",
                json=item,
                headers=sb_headers(),
            )
            if r.status_code not in (200, 201, 204):
                print(f"  ERROR art {i+1}: {r.status_code} {r.text}")
                sys.exit(1)

            print(f"  [{i+1:3}/{len(items)}] {item['title'][:60]}")

            # Respetar rate limit de Gemini (1500 req/min en free tier)
            time.sleep(0.05)

    print("\nListo. Verifica en Supabase:")
    print("  SELECT COUNT(*), COUNT(embedding) FROM legal_documents;")


if __name__ == "__main__":
    main()
