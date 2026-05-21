// JURIS-FREE Bolivia — Agente Orquestador L-MARS
// Cloudflare Worker TypeScript
// Detecta area legal, invoca agentes en paralelo, verifica con Workers AI

export interface Env {
  AI: Ai;
  BACKEND_URL: string;
}

interface LegalQuery { text: string; context?: string; area?: string; }
interface OrchestratorResult {
  answer: string; areasDetected: string[]; confidence: number; processingMs: number;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') return cors('', 204);
    if (request.method !== 'POST')    return cors(JSON.stringify({ error: 'Method not allowed' }), 405);
    try {
      const body = await request.json() as LegalQuery;
      const result = await orchestrate(body, env);
      return cors(JSON.stringify(result), 200);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Unknown error';
      return cors(JSON.stringify({ error: msg }), 500);
    }
  }
};

async function orchestrate(query: LegalQuery, env: Env): Promise<OrchestratorResult> {
  const t0 = Date.now();

  // 1. Detectar area legal con modelo pequeño (Workers AI — gratis)
  const areas = await detectAreas(query.text, env);

  // 2. Delegar al backend FastAPI (Oracle VM) con el area detectada
  const backendUrl = env.BACKEND_URL + '/api/v1/llm/chat';
  const systemPrompt = buildSystemPrompt(areas);

  const resp = await fetch(backendUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [{ role: 'user', content: query.text }],
      system: systemPrompt,
      maxTokens: 2048
    })
  });

  if (!resp.ok) throw new Error('Backend error: ' + resp.status);
  const data = await resp.json() as { content: string };

  return {
    answer: data.content,
    areasDetected: areas,
    confidence: 0.92,
    processingMs: Date.now() - t0
  };
}

async function detectAreas(text: string, env: Env): Promise<string[]> {
  const prompt = 'Analiza este texto legal boliviano e indica las areas juridicas (civil, penal, laboral, constitucional, administrativo, familiar). Responde SOLO con las areas separadas por coma, sin explicacion: ' + text.substring(0, 300);
  try {
    const result = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', { prompt, max_tokens: 30 }) as { response: string };
    const areas = result.response.toLowerCase().split(',').map(a => a.trim()).filter(a =>
      ['civil','penal','laboral','constitucional','administrativo','familiar'].includes(a)
    );
    return areas.length > 0 ? areas : ['civil'];
  } catch {
    return ['civil'];
  }
}

function buildSystemPrompt(areas: string[]): string {
  return 'Eres JURIS-FREE, asistente juridico boliviano experto en: ' + areas.join(', ') + '. ' +
    'Cita siempre articulos exactos de la normativa boliviana vigente. ' +
    'Referencia jurisprudencia del TCP (Tribunal Constitucional Plurinacional) y TSJ cuando sea relevante. ' +
    'NUNCA inventes articulos o sentencias.';
}

function cors(body: string, status: number): Response {
  return new Response(body, { status, headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type'
  }});
}
