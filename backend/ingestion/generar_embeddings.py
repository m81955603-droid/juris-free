"""
JURIS-FREE Bolivia — Generador de Embeddings para Busqueda Semantica
Lee normas_bolivia.json, genera embeddings con sentence-transformers
(modelo multilingue, 384 dims) y los sube a la tabla `legal_documents` en Supabase.

Uso:
    cd backend
    python ingestion/generar_embeddings.py

Requiere en backend/.env:
    SUPABASE_URL
    SUPABASE_SERVICE_KEY
"""

import json
import os
import sys

from dotenv import load_dotenv

# Cargar .env desde backend/ (relativo a este script)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERROR: Faltan SUPABASE_URL / SUPABASE_SERVICE_KEY en backend/.env")
    sys.exit(1)

NORMAS_FILE = os.path.join(BASE_DIR, "normas_bolivia.json")

# Modelo multilingue, 384 dims, corre en CPU sin API externa
MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"


def main():
    print(f"Cargando modelo de embeddings: {MODEL_NAME} (puede tardar la primera vez)...")
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer(MODEL_NAME)

    print(f"Leyendo {NORMAS_FILE}...")
    with open(NORMAS_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    docs = data.get("documentos", [])
    print(f"Normas encontradas: {len(docs)}")

    # Construir lista de "documentos" = articulos individuales
    items = []
    for norma in docs:
        norma_id    = norma.get("id", "")
        norma_titulo = norma.get("titulo", "")
        area        = norma.get("area", "")
        tipo        = norma.get("tipo", "")
        fecha       = norma.get("fecha")

        for art in norma.get("articulos", []):
            numero = art.get("num", "")
            texto  = art.get("texto", "")
            if not texto.strip():
                continue

            # legal_documents.type solo acepta: ley, decreto, sentencia, resolucion, constitucion
            tipo_db = "ley" if tipo == "codigo" else tipo

            # Texto a embeddear: incluye contexto (norma + numero) para mejor recuperacion
            texto_embed = f"{norma_titulo}. Articulo {numero}. {texto}"

            items.append({
                "title":          f"{norma_titulo} — Art. {numero}",
                "body":           texto,
                "type":           tipo_db,
                "area":           area,
                "published_date": fecha,
                "jurisdiction":   "nacional",
                "source_url":     None,
                "metadata":       {
                    "norma_id": norma_id,
                    "norma_titulo": norma_titulo,
                    "articulo_num": numero
                },
                "_embed_text": texto_embed,
            })

    print(f"Total articulos a procesar: {len(items)}")

    print("Generando embeddings (batch)...")
    textos = [it["_embed_text"] for it in items]
    embeddings = model.encode(textos, show_progress_bar=True, batch_size=32)

    for it, emb in zip(items, embeddings):
        it["embedding"] = emb.tolist()
        del it["_embed_text"]

    print("Conectando a Supabase (REST API directo)...")
    import httpx

    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }

    print("Limpiando legal_documents (filas con type en ('ley','codigo','constitucion'))...")
    with httpx.Client(timeout=60) as client:
        del_url = f"{SUPABASE_URL}/rest/v1/legal_documents?type=in.(ley,codigo,constitucion)"
        r = client.delete(del_url, headers=headers)
        if r.status_code not in (200, 204):
            print(f"  Aviso al limpiar: {r.status_code} {r.text}")

        print("Insertando en Supabase...")
        batch_size = 50
        for i in range(0, len(items), batch_size):
            batch = items[i:i + batch_size]
            r = client.post(
                f"{SUPABASE_URL}/rest/v1/legal_documents",
                json=batch,
                headers=headers,
            )
            if r.status_code not in (200, 201, 204):
                print(f"  ERROR insertando batch {i}: {r.status_code} {r.text}")
                sys.exit(1)
            print(f"  Insertados {min(i + batch_size, len(items))}/{len(items)}")

    print("\nListo. Verifica con:")
    print("  select count(*) from legal_documents;")


if __name__ == "__main__":
    main()
