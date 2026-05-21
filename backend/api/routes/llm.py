import httpx, os, time, logging, json
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List

logger = logging.getLogger(__name__)
router = APIRouter()

class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    provider:   Optional[str] = None
    model:      Optional[str] = None
    messages:   List[Message]
    system:     Optional[str] = None
    maxTokens:  int = 4096
    useContext: bool = False
    docType:    Optional[str] = None

class ChatResponse(BaseModel):
    content:    str
    provider:   str
    model:      str
    tokensUsed: int
    latencyMs:  int

PROVIDERS = [
    {"name":"gemini",     "url":"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", "key_env":"GEMINI_API_KEY",     "model":"gemini-2.5-flash",              "fmt":"gemini"},
    {"name":"groq",       "url":"https://api.groq.com/openai/v1/chat/completions",                                          "key_env":"GROQ_API_KEY",       "model":"llama-3.3-70b-versatile",       "fmt":"openai"},
    {"name":"cerebras",   "url":"https://api.cerebras.ai/v1/chat/completions",                                              "key_env":"CEREBRAS_API_KEY",   "model":"llama3.3-70b",                  "fmt":"openai"},
    {"name":"openrouter", "url":"https://openrouter.ai/api/v1/chat/completions",                                            "key_env":"OPENROUTER_API_KEY", "model":"qwen/qwen-2.5-72b-instruct:free","fmt":"openai"},
    {"name":"sambanova",  "url":"https://api.sambanova.ai/v1/chat/completions",                                             "key_env":"SAMBANOVA_API_KEY",  "model":"Meta-Llama-3.3-70B-Instruct",   "fmt":"openai"},
]

_rate_limited: dict = {}
_contexto_cache = None

def get_contexto_generador(doc_type: str = None) -> str:
    global _contexto_cache
    if _contexto_cache is None:
        try:
            f = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                '..', '..', 'ingestion', 'contexto_generador.json')
            with open(f, 'r', encoding='utf-8') as fh:
                _contexto_cache = json.load(fh)
        except Exception as e:
            logger.warning(f"No se pudo cargar contexto: {e}")
            _contexto_cache = {}

    if not _contexto_cache:
        return ""

    # Mapeo tipo documento -> clave en el JSON
    mapa = {
        'demanda-civil':        'ordinario',
        'denuncia-penal':       'coactiva',
        'contrato-compraventa': 'nulidad',
        'memorial':             'ordinario',
        'poder-notarial':       'ordinario',
        'contrato-trabajo':     'ordinario',
    }

    clave = mapa.get(doc_type, 'ordinario') if doc_type else 'ordinario'
    muestras = _contexto_cache.get(clave, [])

    if not muestras:
        # Usar cualquier muestra disponible
        for v in _contexto_cache.values():
            if v:
                muestras = v
                break

    if not muestras:
        return ""

    # Construir contexto con las muestras reales
    contexto = "\n\n=== MUESTRAS REALES DE DOCUMENTOS BOLIVIANOS ===\n"
    contexto += "Usa EXACTAMENTE la misma estructura, encabezados, secciones y estilo juridico de estas muestras reales:\n\n"

    for i, muestra in enumerate(muestras[:2], 1):
        contexto += f"--- MUESTRA {i}: {muestra['nombre']} ---\n"
        contexto += muestra['texto'][:2500]
        contexto += "\n\n"

    contexto += "=== FIN DE MUESTRAS ===\n"
    contexto += "IMPORTANTE: Replica exactamente la estructura anterior. Mismos encabezados, misma forma de identificar autoridad, demandante, demandado, objeto, hechos y petitorio. Solo cambia los datos especificos indicados por el usuario.\n"

    return contexto


async def call_openai(p, messages, system, max_tokens):
    key = os.getenv(p["key_env"])
    if not key: raise ValueError(f"Falta {p['key_env']}")
    msgs = []
    if system: msgs.append({"role":"system","content":system})
    msgs += [{"role":m.role,"content":m.content} for m in messages]
    async with httpx.AsyncClient(timeout=90) as c:
        r = await c.post(p["url"],
            json={"model":p["model"],"messages":msgs,"max_tokens":max_tokens,"temperature":0.1},
            headers={"Authorization":f"Bearer {key}","Content-Type":"application/json"})
        if r.status_code == 429: raise httpx.HTTPStatusError("rate_limit", request=r.request, response=r)
        r.raise_for_status()
        d = r.json()
        return d["choices"][0]["message"]["content"], d.get("usage",{}).get("total_tokens",0)

async def call_gemini(p, messages, system, max_tokens):
    key = os.getenv(p["key_env"])
    if not key: raise ValueError("Falta GEMINI_API_KEY")
    contents = []
    if system:
        contents += [
            {"role":"user","parts":[{"text":f"[Sistema]: {system}"}]},
            {"role":"model","parts":[{"text":"Entendido. Seguire exactamente la estructura de las muestras reales bolivianas proporcionadas."}]}
        ]
    for m in messages:
        contents.append({"role":"model" if m.role=="assistant" else "user","parts":[{"text":m.content}]})
    async with httpx.AsyncClient(timeout=90) as c:
        r = await c.post(f"{p['url']}?key={key}",
            json={"contents":contents,"generationConfig":{"maxOutputTokens":max_tokens,"temperature":0.1}})
        if r.status_code == 429: raise httpx.HTTPStatusError("rate_limit", request=r.request, response=r)
        r.raise_for_status()
        d = r.json()
        return d["candidates"][0]["content"]["parts"][0]["text"], d.get("usageMetadata",{}).get("totalTokenCount",0)

@router.post("/chat", response_model=ChatResponse)
async def chat_completion(req: ChatRequest):
    providers = PROVIDERS.copy()
    if req.provider:
        pref = next((p for p in providers if p["name"]==req.provider), None)
        if pref: providers = [pref]+[p for p in providers if p["name"]!=req.provider]

    # Enriquecer con muestras reales
    system = req.system or ""
    if req.useContext or req.docType:
        system = system + get_contexto_generador(req.docType)

    last_err = None
    for p in providers:
        if p["name"] in _rate_limited and time.time() < _rate_limited[p["name"]]:
            continue
        elif p["name"] in _rate_limited:
            del _rate_limited[p["name"]]
        try:
            t0 = time.time()
            logger.info(f"Intentando {p['name']} (useContext={req.useContext}, docType={req.docType})...")
            if p["fmt"] == "gemini":
                content, tokens = await call_gemini(p, req.messages, system, req.maxTokens)
            else:
                content, tokens = await call_openai(p, req.messages, system, req.maxTokens)
            ms = int((time.time()-t0)*1000)
            logger.info(f"{p['name']} OK - {ms}ms, {tokens} tokens")
            return ChatResponse(content=content, provider=p["name"], model=p["model"], tokensUsed=tokens, latencyMs=ms)
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                _rate_limited[p["name"]] = time.time()+900
            last_err = str(e)
        except Exception as e:
            last_err = str(e)
            logger.error(f"{p['name']} error: {e}")

    raise HTTPException(503, f"Todos los proveedores fallaron. Ultimo error: {last_err}")