from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
import logging
import os
load_dotenv(dotenv_path=r"C:\proyectos\juris-free\backend\.env", override=True)
from .routes import llm, embeddings, health, library, muestras, cases, calendar, clients, documents
logging.basicConfig(level=logging.INFO)

def download_muestras():
    hf_token = os.getenv("HF_TOKEN")
    hf_repo = os.getenv("HF_MUESTRAS_REPO") or os.getenv("HF_DATASET_REPO")
    if not hf_token or not hf_repo:
        logging.info("HF_TOKEN o HF_DATASET_REPO no configurados, saltando descarga")
        return
    muestras_path = "/tmp/muestras"
    if os.path.exists(muestras_path) and len(os.listdir(muestras_path)) > 10:
        logging.info(f"Muestras ya descargadas en {muestras_path}")
        return
    logging.info(f"Descargando muestras desde {hf_repo}...")
    logging.info(f"HF_TOKEN presente: {bool(hf_token)}, REPO: {hf_repo}")
    try:
        from huggingface_hub import snapshot_download
        snapshot_download(
            repo_id=hf_repo,
            repo_type="dataset",
            local_dir=muestras_path,
            token=hf_token,
            ignore_patterns=["*.gitattributes", "*.md"]
        )
        logging.info("Muestras descargadas correctamente")
    except Exception as e:
        logging.error(f"Error descargando muestras: {e}")

async def run_daily_scraper():
    """Corre el scraper de Gaceta Oficial cada 24 horas"""
    import asyncio
    while True:
        try:
            await asyncio.sleep(24 * 60 * 60)  # Esperar 24 horas
            logging.info("Iniciando scraper diario de Gaceta Oficial...")
            from ingestion.scraper_gaceta import run_scraper
            run_scraper(dias=1)
            logging.info("Scraper diario completado")
        except Exception as e:
            logging.error(f"Error en scraper diario: {e}")

@asynccontextmanager
async def lifespan(app: FastAPI):
    import asyncio
    logging.info("JURIS-FREE Bolivia API iniciando...")
    logging.info(f"Gemini:     {'OK' if os.getenv('GEMINI_API_KEY') else 'FALTA'}")
    logging.info(f"Groq:       {'OK' if os.getenv('GROQ_API_KEY') else 'FALTA'}")
    logging.info(f"Cerebras:   {'OK' if os.getenv('CEREBRAS_API_KEY') else 'FALTA'}")
    logging.info(f"OpenRouter: {'OK' if os.getenv('OPENROUTER_API_KEY') else 'FALTA'}")
    logging.info(f"SambaNova:  {'OK' if os.getenv('SAMBANOVA_API_KEY') else 'FALTA'}")
    download_muestras()
    from .routes.muestras import build_index
    idx = build_index()
    logging.info(f"Muestras indexadas: {len(idx)} archivos Word")
    # Iniciar scraper diario en background
    asyncio.create_task(run_daily_scraper())
    yield
    logging.info("JURIS-FREE Bolivia API iniciando...")
    logging.info(f"Gemini:     {'OK' if os.getenv('GEMINI_API_KEY') else 'FALTA'}")
    logging.info(f"Groq:       {'OK' if os.getenv('GROQ_API_KEY') else 'FALTA'}")
    logging.info(f"Cerebras:   {'OK' if os.getenv('CEREBRAS_API_KEY') else 'FALTA'}")
    logging.info(f"OpenRouter: {'OK' if os.getenv('OPENROUTER_API_KEY') else 'FALTA'}")
    logging.info(f"SambaNova:  {'OK' if os.getenv('SAMBANOVA_API_KEY') else 'FALTA'}")
    download_muestras()
    from .routes.muestras import build_index
    idx = build_index()
    logging.info(f"Muestras indexadas: {len(idx)} archivos Word")
    yield

app = FastAPI(title="JURIS-FREE Bolivia API", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"])
app.include_router(health.router)
app.include_router(llm.router,       prefix="/api/v1/llm",       tags=["LLM"])
app.include_router(embeddings.router, prefix="/api/v1/embeddings", tags=["Embeddings"])
app.include_router(library.router,   prefix="/api/v1/library",   tags=["Biblioteca"])
app.include_router(cases.router,    prefix="/api/v1/cases",    tags=["Casos"])
app.include_router(calendar.router,  prefix="/api/v1/calendar",  tags=["Calendario"])
app.include_router(clients.router,  prefix="/api/v1",         tags=["Clientes"])
app.include_router(muestras.router,  prefix="/api/v1/muestras",  tags=["Muestras"])
app.include_router(documents.router, prefix="/api/v1/documents", tags=["Documentos"])
