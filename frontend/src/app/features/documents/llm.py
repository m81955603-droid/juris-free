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
    maxTokens:  int = 65536
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
@router.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    """Endpoint de streaming — devuelve tokens en tiempo real via SSE"""
    from fastapi.responses import StreamingResponse
    import json

    providers = PROVIDERS.copy()
    if req.provider:
        pref = next((p for p in providers if p["name"] == req.provider), None)
        if pref: providers = [pref] + [p for p in providers if p["name"] != req.provider]

    system = req.system or ""
    if req.useContext or req.docType:
        system = system + get_contexto_generador(req.docType)

    async def generate():
        last_err = None
        for p in providers:
            if p["name"] in _rate_limited and time.time() < _rate_limited[p["name"]]:
                continue
            elif p["name"] in _rate_limited:
                del _rate_limited[p["name"]]
            try:
                logger.info(f"Streaming con {p['name']}...")
                if p["fmt"] == "gemini":
                    content, tokens = await call_gemini(p, req.messages, system, req.maxTokens)
                else:
                    content, tokens = await call_openai(p, req.messages, system, req.maxTokens)

                # Simular streaming dividiendo la respuesta en chunks
                words = content.split(' ')
                for i, word in enumerate(words):
                    chunk = word + (' ' if i < len(words) - 1 else '')
                    data = json.dumps({"chunk": chunk, "done": False, "provider": p["name"]})
                    yield f"data: {data}\n\n"
                    await asyncio.sleep(0.02)

                # Señal de fin
                data = json.dumps({"chunk": "", "done": True, "provider": p["name"], "model": p["model"], "tokens": tokens})
                yield f"data: {data}\n\n"
                return

            except httpx.HTTPStatusError as e:
                if e.response.status_code == 429:
                    _rate_limited[p["name"]] = time.time() + 900
                last_err = str(e)
            except Exception as e:
                last_err = str(e)
                logger.error(f"{p['name']} stream error: {e}")

        error_data = json.dumps({"error": f"Todos los proveedores fallaron: {last_err}", "done": True})
        yield f"data: {error_data}\n\n"

    import asyncio
    return StreamingResponse(generate(), media_type="text/event-stream", headers={
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no"
    })


# ─────────────────────────────────────────────────────────────
# CRITIC-LOOP: Generar → Revisar → Entregar documento blindado
# ─────────────────────────────────────────────────────────────

CRITIC_SYSTEM = """Eres un abogado senior boliviano con 20 años de experiencia revisando el trabajo de pasantes.
Tu tarea es revisar el borrador de documento legal y encontrar TODOS los problemas.

Busca especificamente:
1. FALTA DE PERSONERIA: ¿Estan correctamente identificadas todas las partes con CI/NIT?
2. OSCURIDAD EN LA DEMANDA: ¿El petitorio es claro y especifico?
3. PRESCRIPCION: ¿Menciona plazos que podrian estar vencidos?
4. ARTICULOS INCORRECTOS: ¿Las citas legales son correctas para Bolivia 2026?
5. CLAUSULAS AMBIGUAS: ¿Hay terminos que podrian interpretarse de multiples formas?
6. FALTA DE REQUISITOS FORMALES: ¿Cumple con todos los requisitos del tipo de documento?
7. INCONSISTENCIAS: ¿Hay contradicciones entre clausulas o secciones?

Responde SOLO en JSON con esta estructura exacta:
{
  "puntaje_riesgo": 0-100,
  "problemas": ["problema 1", "problema 2", ...],
  "requiere_correccion": true/false,
  "instrucciones_correccion": "instrucciones especificas para corregir el documento"
}

Si el puntaje es menor a 20, no se necesita correccion. Sin texto adicional fuera del JSON."""

CORRECTOR_SYSTEM = """Eres un abogado boliviano experto. Recibes un borrador de documento legal y una lista de problemas identificados por un revisor senior.

Tu tarea es corregir TODOS los problemas mencionados y entregar el documento final perfecto.
- Mantén la estructura y estilo del borrador original
- Corrige exactamente los problemas señalados
- Agrega lo que falte, elimina lo ambiguo
- El documento debe estar listo para presentar ante autoridad judicial boliviana
- Usa terminología jurídica boliviana correcta y vigente 2026"""

class CriticLoopRequest(BaseModel):
    messages:   List[Message]
    system:     Optional[str] = None
    docType:    Optional[str] = None
    useContext: bool = True

class CriticLoopResponse(BaseModel):
    documento_final: str
    puntaje_riesgo:  int
    problemas:       List[str]
    corregido:       bool
    provider:        str
    iteraciones:     int

@router.post("/chat/critic-loop", response_model=CriticLoopResponse)
async def critic_loop(req: CriticLoopRequest):
    """
    Flujo Critic-Loop en 2-3 pasos:
    1. Genera borrador con el LLM principal
    2. Un segundo LLM actua como revisor critico (abogado senior)
    3. Si riesgo > 20%, un tercer LLM corrige el documento
    Devuelve el documento final blindado juridicamente.
    """
    # Enriquecer con muestras reales
    system = req.system or ""
    if req.useContext or req.docType:
        system = system + get_contexto_generador(req.docType)

    # ── PASO 1: Generar borrador ──────────────────────────────
    logger.info("Critic-Loop PASO 1: Generando borrador inicial...")
    borrador = None
    provider_usado = ""

    for p in PROVIDERS:
        if p["name"] in _rate_limited and time.time() < _rate_limited[p["name"]]:
            continue
        try:
            if p["fmt"] == "gemini":
                borrador, _ = await call_gemini(p, req.messages, system, 8000)
            else:
                borrador, _ = await call_openai(p, req.messages, system, 8000)
            provider_usado = p["name"]
            logger.info(f"Borrador generado con {p['name']}")
            break
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                _rate_limited[p["name"]] = time.time() + 900
        except Exception as e:
            logger.error(f"Error generando borrador con {p['name']}: {e}")

    if not borrador:
        raise HTTPException(503, "No se pudo generar el borrador inicial")

    # ── PASO 2: Revisar con critic (segundo proveedor) ────────
    logger.info("Critic-Loop PASO 2: Revisando con abogado senior...")
    critica = None
    proveedores_critica = [p for p in PROVIDERS if p["name"] != provider_usado]

    critica_msg = [Message(
        role="user",
        content=f"Revisa este documento legal boliviano y encuentra todos los problemas:\n\n{borrador}"
    )]

    for p in proveedores_critica:
        if p["name"] in _rate_limited and time.time() < _rate_limited[p["name"]]:
            continue
        try:
            if p["fmt"] == "gemini":
                critica_raw, _ = await call_gemini(p, critica_msg, CRITIC_SYSTEM, 2000)
            else:
                critica_raw, _ = await call_openai(p, critica_msg, CRITIC_SYSTEM, 2000)

            # Parsear JSON de la crítica
            critica_json = critica_raw.strip()
            critica_json = critica_json.replace("```json", "").replace("```", "").strip()
            critica = json.loads(critica_json)
            logger.info(f"Critica completada. Puntaje riesgo: {critica.get('puntaje_riesgo', 0)}")
            break
        except json.JSONDecodeError:
            # Si no devuelve JSON válido, asumir sin problemas
            critica = {"puntaje_riesgo": 0, "problemas": [], "requiere_correccion": False, "instrucciones_correccion": ""}
            break
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                _rate_limited[p["name"]] = time.time() + 900
        except Exception as e:
            logger.error(f"Error en critica con {p['name']}: {e}")

    if not critica:
        # Si falla la crítica, devolver el borrador directamente
        return CriticLoopResponse(
            documento_final=borrador,
            puntaje_riesgo=0,
            problemas=[],
            corregido=False,
            provider=provider_usado,
            iteraciones=1
        )

    puntaje = critica.get("puntaje_riesgo", 0)
    problemas = critica.get("problemas", [])
    requiere = critica.get("requiere_correccion", False) or puntaje > 20

    # ── PASO 3: Corregir si puntaje > 20% ────────────────────
    if not requiere:
        logger.info(f"Critic-Loop: puntaje {puntaje} < 20, documento aprobado sin correcciones")
        return CriticLoopResponse(
            documento_final=borrador,
            puntaje_riesgo=puntaje,
            problemas=problemas,
            corregido=False,
            provider=provider_usado,
            iteraciones=2
        )

    logger.info(f"Critic-Loop PASO 3: Corrigiendo (puntaje riesgo: {puntaje})...")
    instrucciones = critica.get("instrucciones_correccion", "Corrige todos los problemas identificados")
    problemas_str = "\n".join(f"- {p}" for p in problemas)

    corrector_msg = [Message(
        role="user",
        content=f"""BORRADOR ORIGINAL:
{borrador}

PROBLEMAS IDENTIFICADOS POR EL REVISOR:
{problemas_str}

INSTRUCCIONES DE CORRECCIÓN:
{instrucciones}

Genera el documento corregido y perfecto."""
    )]

    documento_final = borrador  # fallback
    for p in PROVIDERS:
        if p["name"] in _rate_limited and time.time() < _rate_limited[p["name"]]:
            continue
        try:
            if p["fmt"] == "gemini":
                documento_final, _ = await call_gemini(p, corrector_msg, CORRECTOR_SYSTEM, 8000)
            else:
                documento_final, _ = await call_openai(p, corrector_msg, CORRECTOR_SYSTEM, 8000)
            logger.info(f"Corrección completada con {p['name']}")
            break
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                _rate_limited[p["name"]] = time.time() + 900
        except Exception as e:
            logger.error(f"Error en corrección con {p['name']}: {e}")

    return CriticLoopResponse(
        documento_final=documento_final,
        puntaje_riesgo=puntaje,
        problemas=problemas,
        corregido=True,
        provider=provider_usado,
        iteraciones=3
    )
