# Embeddings con sentence-transformers (corre en Oracle VM gratis)
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List
import logging

logger = logging.getLogger(__name__)
router = APIRouter()

class EmbedRequest(BaseModel):
    texts: List[str]
    model: str = "all-MiniLM-L6-v2"

class EmbedResponse(BaseModel):
    embeddings: List[List[float]]
    model: str
    dimensions: int

_model_cache = {}

def get_model(model_name: str):
    if model_name not in _model_cache:
        try:
            from sentence_transformers import SentenceTransformer
            logger.info(f"Cargando modelo {model_name}...")
            _model_cache[model_name] = SentenceTransformer(model_name)
            logger.info(f"Modelo {model_name} cargado OK")
        except Exception as e:
            raise HTTPException(500, f"Error cargando modelo: {e}")
    return _model_cache[model_name]

@router.post("/embed", response_model=EmbedResponse)
async def embed_texts(req: EmbedRequest):
    model = get_model(req.model)
    embeddings = model.encode(req.texts, convert_to_list=True)
    return EmbedResponse(embeddings=embeddings, model=req.model, dimensions=len(embeddings[0]))
