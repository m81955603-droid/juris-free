#Requires -Version 7.0
<#
.SYNOPSIS
    JURIS-FREE Bolivia — Script de configuración maestro
    Sistema jurídico open source con IA para abogados bolivianos

.DESCRIPTION
    Configura desde cero:
    - Proyecto Angular 17 + TypeScript (frontend PWA)
    - Backend FastAPI en Python (para Oracle VM)
    - Cloudflare Workers (agentes L-MARS en TypeScript)
    - Proxy LLM multi-proveedor (Gemini, Groq, Cerebras, OpenRouter, SambaNova)
    - Supabase + pgvector (base de datos vectorial)
    - Pipeline de ingestión legal Bolivia (Gaceta Oficial, TCP, Órgano Judicial)
    - GitHub Actions (keep-alive anti-pausa + CI/CD)

.NOTES
    Autor: JURIS-FREE Project
    Versión: 1.0.0 — Mayo 2026
    Plataforma: Windows 10/11, macOS, Linux (PowerShell 7+)
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Directorio raíz del proyecto")]
    [string]$ProjectRoot = ".\juris-free-bolivia",

    [Parameter(HelpMessage="Omite verificación de dependencias")]
    [switch]$SkipDepsCheck,

    [Parameter(HelpMessage="Solo configura el frontend Angular")]
    [switch]$FrontendOnly,

    [Parameter(HelpMessage="Solo configura los Workers de Cloudflare")]
    [switch]$WorkersOnly,

    [Parameter(HelpMessage="Solo configura el backend FastAPI")]
    [switch]$BackendOnly,

    [Parameter(HelpMessage="Modo verbose para debugging")]
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Paleta de colores para output ────────────────────────────────────────────
function Write-Header  { param([string]$msg) Write-Host "`n━━━ $msg ━━━" -ForegroundColor Cyan }
function Write-Step    { param([string]$msg) Write-Host "  ▸ $msg" -ForegroundColor White }
function Write-OK      { param([string]$msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn    { param([string]$msg) Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail    { param([string]$msg) Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Info    { param([string]$msg) Write-Host "  ℹ $msg" -ForegroundColor DarkCyan }

function Show-Banner {
    $banner = @"

  ██╗██╗   ██╗██████╗ ██╗███████╗      ███████╗██████╗ ███████╗███████╗
  ██║██║   ██║██╔══██╗██║██╔════╝      ██╔════╝██╔══██╗██╔════╝██╔════╝
  ██║██║   ██║██████╔╝██║███████╗      █████╗  ██████╔╝█████╗  █████╗
  ██║██║   ██║██╔══██╗██║╚════██║      ██╔══╝  ██╔══██╗██╔══╝  ██╔══╝
  ██║╚██████╔╝██║  ██║██║███████║      ██║     ██║  ██║███████╗███████╗
  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝      ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝

  Sistema Jurídico Inteligente para Bolivia — 100% Gratuito y Open Source
  Stack: Angular 17 + TypeScript | FastAPI | Cloudflare Workers | Supabase

"@
    Write-Host $banner -ForegroundColor Cyan
}

# ─── 1. VERIFICACIÓN DE DEPENDENCIAS ─────────────────────────────────────────
function Test-Dependencies {
    Write-Header "Verificando dependencias del sistema"

    $deps = @(
        @{ Name = "Node.js 18+";  Cmd = "node";    Args = "--version"; MinVer = "18.0.0" },
        @{ Name = "npm 9+";       Cmd = "npm";     Args = "--version"; MinVer = "9.0.0"  },
        @{ Name = "Python 3.10+"; Cmd = "python3"; Args = "--version"; MinVer = "3.10.0" },
        @{ Name = "Git 2.x";      Cmd = "git";     Args = "--version"; MinVer = "2.0.0"  }
    )

    $optional = @(
        @{ Name = "Wrangler CLI (Cloudflare)"; Cmd = "wrangler"; Args = "--version" },
        @{ Name = "Angular CLI";               Cmd = "ng";       Args = "version --skip-git" },
        @{ Name = "Supabase CLI";              Cmd = "supabase"; Args = "--version" }
    )

    $allOk = $true
    foreach ($dep in $deps) {
        try {
            $ver = & $dep.Cmd $dep.Args 2>&1 | Select-String -Pattern '\d+\.\d+' | Select-Object -First 1
            Write-OK "$($dep.Name) — $ver"
        }
        catch {
            Write-Fail "$($dep.Name) NO encontrado. Instala desde: https://nodejs.org"
            $allOk = $false
        }
    }

    Write-Info "Dependencias opcionales (se instalarán si faltan):"
    foreach ($dep in $optional) {
        try {
            $ver = & $dep.Cmd $dep.Args 2>&1 | Select-Object -First 1
            Write-OK "$($dep.Name) — $ver"
        }
        catch {
            Write-Warn "$($dep.Name) — se instalará automáticamente"
        }
    }

    if (-not $allOk) {
        throw "Faltan dependencias requeridas. Instálalas y vuelve a ejecutar."
    }
}

# ─── 2. INSTALAR HERRAMIENTAS GLOBALES ────────────────────────────────────────
function Install-GlobalTools {
    Write-Header "Instalando herramientas globales"

    $tools = @(
        @{ Name = "Angular CLI 17";     Pkg = "@angular/cli@17"     },
        @{ Name = "Wrangler CLI";       Pkg = "wrangler"             },
        @{ Name = "TypeScript 5.x";     Pkg = "typescript"           },
        @{ Name = "ts-node";            Pkg = "ts-node"              },
        @{ Name = "Supabase CLI";       Pkg = "supabase"             }
    )

    foreach ($tool in $tools) {
        Write-Step "Instalando $($tool.Name)..."
        try {
            npm install -g $tool.Pkg --silent 2>&1 | Out-Null
            Write-OK "$($tool.Name) instalado"
        }
        catch {
            Write-Warn "Error instalando $($tool.Name): $_"
        }
    }
}

# ─── 3. CREAR ESTRUCTURA DE DIRECTORIOS ──────────────────────────────────────
function New-ProjectStructure {
    Write-Header "Creando estructura del proyecto"

    $dirs = @(
        # Frontend Angular
        "$ProjectRoot/frontend",

        # Backend Python (Oracle VM)
        "$ProjectRoot/backend",
        "$ProjectRoot/backend/api",
        "$ProjectRoot/backend/api/routes",
        "$ProjectRoot/backend/api/models",
        "$ProjectRoot/backend/agents",
        "$ProjectRoot/backend/ingestion",
        "$ProjectRoot/backend/embeddings",

        # Cloudflare Workers (TypeScript)
        "$ProjectRoot/workers",
        "$ProjectRoot/workers/orchestrator",
        "$ProjectRoot/workers/agent-civil",
        "$ProjectRoot/workers/agent-penal",
        "$ProjectRoot/workers/agent-laboral",
        "$ProjectRoot/workers/agent-constitutional",
        "$ProjectRoot/workers/agent-judge",
        "$ProjectRoot/workers/agent-verifier",
        "$ProjectRoot/workers/llm-proxy",
        "$ProjectRoot/workers/shared",

        # Infraestructura
        "$ProjectRoot/infra",
        "$ProjectRoot/infra/github-actions",
        "$ProjectRoot/infra/oracle-vm",
        "$ProjectRoot/infra/cloudflare",
        "$ProjectRoot/infra/supabase",

        # Scripts PowerShell
        "$ProjectRoot/scripts",

        # Datos legales Bolivia
        "$ProjectRoot/data/raw",
        "$ProjectRoot/data/processed",
        "$ProjectRoot/data/embeddings"
    )

    foreach ($dir in $dirs) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Step "Creado: $dir"
    }

    Write-OK "Estructura de directorios creada"
}

# ─── 4. FRONTEND ANGULAR 17 PWA ──────────────────────────────────────────────
function New-AngularProject {
    Write-Header "Creando proyecto Angular 17 (PWA)"

    $frontendPath = "$ProjectRoot/frontend"

    Write-Step "Generando app Angular con routing y SCSS..."
    Set-Location $ProjectRoot
    ng new juris-free-app `
        --directory frontend `
        --routing true `
        --style scss `
        --strict true `
        --skip-git true `
        --skip-tests false `
        --standalone true 2>&1 | Out-Null

    Set-Location $frontendPath

    Write-Step "Agregando PWA support..."
    ng add @angular/pwa --skip-confirmation 2>&1 | Out-Null

    Write-Step "Instalando dependencias del proyecto..."
    $npmDeps = @(
        "@supabase/supabase-js",      # Cliente Supabase
        "@angular/material",           # UI components
        "@angular/cdk",               # Component dev kit
        "marked",                      # Markdown rendering
        "dompurify",                   # Sanitización HTML
        "@types/dompurify",
        "rxjs",                        # Reactivo (ya incluido)
        "zone.js",                     # Angular zones
        "highlight.js",                # Syntax highlighting para código legal
        "ngx-markdown"                 # Markdown para Angular
    )

    $npmDevDeps = @(
        "@types/node",
        "tailwindcss",
        "postcss",
        "autoprefixer"
    )

    Write-Step "Instalando dependencias de producción..."
    npm install @supabase/supabase-js @angular/material @angular/cdk marked dompurify @types/dompurify highlight.js ngx-markdown --save 2>&1 | Out-Null

    Write-Step "Instalando dependencias de desarrollo..."
    npm install @types/node tailwindcss postcss autoprefixer --save-dev 2>&1 | Out-Null

    Write-OK "Proyecto Angular configurado"
    Set-Location (Resolve-Path "$ProjectRoot/..")
}

# ─── 5. GENERAR ARCHIVOS ANGULAR (MÓDULOS, SERVICIOS, COMPONENTES) ────────────
function New-AngularModules {
    Write-Header "Generando módulos y servicios Angular"

    $appPath = "$ProjectRoot/frontend/src/app"

    # Crear estructura de módulos
    $ngStructure = @(
        # Módulos de features
        "core",
        "shared",
        "features/chat",
        "features/library",
        "features/cases",
        "features/settings",

        # Servicios
        "core/services",
        "core/guards",
        "core/interceptors",
        "core/models",

        # Componentes compartidos
        "shared/components",
        "shared/pipes",
        "shared/directives"
    )

    foreach ($dir in $ngStructure) {
        New-Item -ItemType Directory -Path "$appPath/$dir" -Force | Out-Null
    }

    Write-OK "Estructura Angular creada"

    # Generar archivos TypeScript principales
    New-LlmProxyService
    New-SupabaseService
    New-ChatComponent
    New-AppRouting
    New-EnvironmentFiles
    New-TailwindConfig
    New-AngularMaterial
}

function New-LlmProxyService {
    Write-Step "Generando LLM Proxy Service (TypeScript)..."

    $content = @'
// src/app/core/services/llm-proxy.service.ts
// Servicio Angular para el proxy agregador de LLMs gratuitos
// Proveedores: Gemini 2.5 Flash | Groq Llama 3.3 | Cerebras | OpenRouter | SambaNova

import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, from, throwError, EMPTY } from 'rxjs';
import { catchError, retry, switchMap, tap } from 'rxjs/operators';
import { environment } from '../../../environments/environment';

export interface LlmMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface LlmResponse {
  content: string;
  provider: string;
  model: string;
  tokensUsed: number;
  latencyMs: number;
}

export interface LlmStreamChunk {
  delta: string;
  done: boolean;
  provider?: string;
}

interface ProviderConfig {
  name: string;
  baseUrl: string;
  model: string;
  apiKeyEnvVar: string;
  maxTokensPerMin: number;
  maxRequestsPerDay: number;
  priority: number;
  supportsStreaming: boolean;
}

@Injectable({ providedIn: 'root' })
export class LlmProxyService {
  private http = inject(HttpClient);

  // Orden de prioridad según free tiers verificados mayo 2026
  private readonly providers: ProviderConfig[] = [
    {
      name: 'gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.5-flash',
      apiKeyEnvVar: 'GEMINI_API_KEY',
      maxTokensPerMin: 1_000_000,
      maxRequestsPerDay: 1_500,
      priority: 1,
      supportsStreaming: true
    },
    {
      name: 'groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      apiKeyEnvVar: 'GROQ_API_KEY',
      maxTokensPerMin: 60_000,
      maxRequestsPerDay: 14_400,
      priority: 2,
      supportsStreaming: true
    },
    {
      name: 'cerebras',
      baseUrl: 'https://api.cerebras.ai/v1',
      model: 'llama3.3-70b',
      apiKeyEnvVar: 'CEREBRAS_API_KEY',
      maxTokensPerMin: 60_000,
      maxRequestsPerDay: 14_400,
      priority: 3,
      supportsStreaming: true
    },
    {
      name: 'openrouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'qwen/qwen-2.5-72b-instruct:free',
      apiKeyEnvVar: 'OPENROUTER_API_KEY',
      maxTokensPerMin: 20_000,
      maxRequestsPerDay: 200,
      priority: 4,
      supportsStreaming: true
    },
    {
      name: 'sambanova',
      baseUrl: 'https://api.sambanova.ai/v1',
      model: 'Meta-Llama-3.3-70B-Instruct',
      apiKeyEnvVar: 'SAMBANOVA_API_KEY',
      maxTokensPerMin: 40_000,
      maxRequestsPerDay: 1_000,
      priority: 5,
      supportsStreaming: true
    }
  ];

  // Tracking de uso por proveedor (persiste en localStorage)
  private usageKey = 'juris_llm_usage';

  /**
   * Envía una consulta legal al mejor proveedor disponible.
   * Falla automáticamente al siguiente si hay rate limit.
   */
  chat(
    messages: LlmMessage[],
    systemPrompt?: string,
    preferredProvider?: string
  ): Observable<LlmResponse> {
    const orderedProviders = this.getOrderedProviders(preferredProvider);

    return this.tryProviders(messages, systemPrompt, orderedProviders, 0);
  }

  /**
   * Streaming de respuesta para UI fluida.
   * Retorna un AsyncGenerator que emite chunks de texto.
   */
  chatStream(
    messages: LlmMessage[],
    systemPrompt?: string,
    preferredProvider?: string
  ): Observable<LlmStreamChunk> {
    // El streaming se maneja via Cloudflare Worker (backend)
    // Aquí usamos Server-Sent Events
    return new Observable(observer => {
      const url = `${environment.apiUrl}/api/v1/chat/stream`;
      const eventSource = new EventSource(url);

      // Enviar request via POST primero, luego escuchar SSE
      this.http.post<{ streamId: string }>(url, {
        messages,
        system: systemPrompt,
        provider: preferredProvider
      }).subscribe({
        next: ({ streamId }) => {
          const sseUrl = `${environment.apiUrl}/api/v1/chat/stream/${streamId}`;
          const es = new EventSource(sseUrl);

          es.onmessage = (event) => {
            const data = JSON.parse(event.data) as LlmStreamChunk;
            observer.next(data);
            if (data.done) {
              es.close();
              observer.complete();
            }
          };

          es.onerror = () => {
            es.close();
            observer.error(new Error('SSE stream error'));
          };
        },
        error: (err) => observer.error(err)
      });

      return () => eventSource.close();
    });
  }

  private tryProviders(
    messages: LlmMessage[],
    systemPrompt: string | undefined,
    providers: ProviderConfig[],
    index: number
  ): Observable<LlmResponse> {
    if (index >= providers.length) {
      return throwError(() => new Error('Todos los proveedores LLM fallaron. Intenta más tarde.'));
    }

    const provider = providers[index];
    const start = Date.now();

    return this.callProvider(provider, messages, systemPrompt).pipe(
      tap(response => {
        this.trackUsage(provider.name, response.tokensUsed);
      }),
      catchError(err => {
        // Rate limit o error de red: probar siguiente proveedor
        console.warn(`[LLM] ${provider.name} falló (${err.message}), probando siguiente...`);
        this.markRateLimited(provider.name);
        return this.tryProviders(messages, systemPrompt, providers, index + 1);
      })
    );
  }

  private callProvider(
    provider: ProviderConfig,
    messages: LlmMessage[],
    systemPrompt?: string
  ): Observable<LlmResponse> {
    // Delegar al backend FastAPI (que corre en Oracle VM)
    // El backend tiene las API keys seguras y maneja el rate limiting
    return this.http.post<LlmResponse>(
      `${environment.apiUrl}/api/v1/llm/chat`,
      {
        provider: provider.name,
        model: provider.model,
        messages,
        system: systemPrompt,
        maxTokens: 2048
      },
      {
        headers: new HttpHeaders({
          'Content-Type': 'application/json',
          'X-Client-Version': '1.0.0'
        })
      }
    );
  }

  private getOrderedProviders(preferred?: string): ProviderConfig[] {
    const available = this.providers.filter(p => !this.isRateLimited(p.name));
    if (preferred) {
      const pref = available.find(p => p.name === preferred);
      if (pref) {
        return [pref, ...available.filter(p => p.name !== preferred)];
      }
    }
    return available.sort((a, b) => a.priority - b.priority);
  }

  private trackUsage(provider: string, tokens: number): void {
    const usage = this.getUsage();
    const today = new Date().toDateString();

    if (!usage[provider]) usage[provider] = {};
    if (!usage[provider][today]) usage[provider][today] = { requests: 0, tokens: 0 };

    usage[provider][today].requests++;
    usage[provider][today].tokens += tokens;
    localStorage.setItem(this.usageKey, JSON.stringify(usage));
  }

  private markRateLimited(provider: string): void {
    const key = `juris_ratelimit_${provider}`;
    // Marcar como limitado por 15 minutos
    localStorage.setItem(key, (Date.now() + 15 * 60 * 1000).toString());
  }

  private isRateLimited(provider: string): boolean {
    const key = `juris_ratelimit_${provider}`;
    const until = localStorage.getItem(key);
    if (!until) return false;
    if (Date.now() > parseInt(until)) {
      localStorage.removeItem(key);
      return false;
    }
    return true;
  }

  private getUsage(): Record<string, Record<string, { requests: number; tokens: number }>> {
    try {
      return JSON.parse(localStorage.getItem(this.usageKey) || '{}');
    } catch {
      return {};
    }
  }

  /**
   * Estadísticas de uso para el panel de configuración
   */
  getUsageStats(): { provider: string; todayRequests: number; todayTokens: number; isLimited: boolean }[] {
    const usage = this.getUsage();
    const today = new Date().toDateString();

    return this.providers.map(p => ({
      provider: p.name,
      model: p.model,
      todayRequests: usage[p.name]?.[today]?.requests ?? 0,
      todayTokens: usage[p.name]?.[today]?.tokens ?? 0,
      isLimited: this.isRateLimited(p.name),
      dailyLimit: p.maxRequestsPerDay
    }));
  }
}
'@

    Set-Content -Path "$ProjectRoot/frontend/src/app/core/services/llm-proxy.service.ts" -Value $content
    Write-OK "LLM Proxy Service generado"
}

function New-SupabaseService {
    Write-Step "Generando Supabase Service..."

    $content = @'
// src/app/core/services/supabase.service.ts
// Servicio Angular para Supabase: Auth + PostgreSQL + pgvector

import { Injectable, inject } from '@angular/core';
import {
  createClient,
  SupabaseClient,
  User,
  Session,
  AuthError
} from '@supabase/supabase-js';
import { BehaviorSubject, Observable, from } from 'rxjs';
import { map } from 'rxjs/operators';
import { environment } from '../../../environments/environment';

export interface LegalDocument {
  id: string;
  type: 'ley' | 'decreto' | 'sentencia' | 'resolucion' | 'constitucion';
  title: string;
  body: string;
  source_url?: string;
  published_date?: string;
  jurisdiction: 'nacional' | 'departamental' | string;
  area: 'civil' | 'penal' | 'laboral' | 'constitucional' | 'administrativo' | 'comercial';
  embedding?: number[];
  metadata: Record<string, unknown>;
}

export interface ConversationMessage {
  id: string;
  conversation_id: string;
  role: 'user' | 'assistant';
  content: string;  // Encriptado en reposo
  created_at: string;
  provider_used?: string;
  tokens_used?: number;
}

export interface Conversation {
  id: string;
  user_id: string;
  title: string;
  area: string;
  created_at: string;
  updated_at: string;
  message_count: number;
}

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  private client: SupabaseClient;
  private _currentUser = new BehaviorSubject<User | null>(null);
  private _session = new BehaviorSubject<Session | null>(null);

  readonly currentUser$ = this._currentUser.asObservable();
  readonly session$ = this._session.asObservable();
  readonly isAuthenticated$ = this.currentUser$.pipe(map(u => !!u));

  constructor() {
    this.client = createClient(
      environment.supabaseUrl,
      environment.supabaseAnonKey,
      {
        auth: {
          autoRefreshToken: true,
          persistSession: true,
          detectSessionInUrl: true
        }
      }
    );

    // Escuchar cambios de autenticación
    this.client.auth.onAuthStateChange((event, session) => {
      this._session.next(session);
      this._currentUser.next(session?.user ?? null);
    });

    // Inicializar con sesión existente
    this.client.auth.getSession().then(({ data: { session } }) => {
      this._session.next(session);
      this._currentUser.next(session?.user ?? null);
    });
  }

  // ─── AUTENTICACIÓN ────────────────────────────────────────────────────────

  signInWithGoogle(): Observable<void> {
    return from(
      this.client.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: `${window.location.origin}/auth/callback` }
      }).then(({ error }) => {
        if (error) throw error;
      })
    );
  }

  signInWithMagicLink(email: string): Observable<void> {
    return from(
      this.client.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: `${window.location.origin}/auth/callback` }
      }).then(({ error }) => {
        if (error) throw error;
      })
    );
  }

  signOut(): Observable<void> {
    return from(
      this.client.auth.signOut().then(({ error }) => {
        if (error) throw error;
      })
    );
  }

  // ─── BÚSQUEDA SEMÁNTICA (pgvector) ────────────────────────────────────────

  /**
   * Búsqueda semántica en la base de conocimiento jurídico boliviano.
   * Usa la función PostgreSQL `match_legal_documents` con pgvector.
   */
  searchLegal(
    queryEmbedding: number[],
    area?: string,
    limit = 5,
    threshold = 0.7
  ): Observable<LegalDocument[]> {
    return from(
      this.client.rpc('match_legal_documents', {
        query_embedding: queryEmbedding,
        match_threshold: threshold,
        match_count: limit,
        filter_area: area ?? null
      }).then(({ data, error }) => {
        if (error) throw error;
        return (data as LegalDocument[]) ?? [];
      })
    );
  }

  /**
   * Búsqueda híbrida: texto completo + semántica
   */
  searchLegalHybrid(
    textQuery: string,
    queryEmbedding: number[],
    area?: string,
    limit = 5
  ): Observable<LegalDocument[]> {
    return from(
      this.client.rpc('hybrid_search_legal', {
        text_query: textQuery,
        query_embedding: queryEmbedding,
        match_count: limit,
        filter_area: area ?? null
      }).then(({ data, error }) => {
        if (error) throw error;
        return (data as LegalDocument[]) ?? [];
      })
    );
  }

  // ─── CONVERSACIONES ───────────────────────────────────────────────────────

  getConversations(userId: string): Observable<Conversation[]> {
    return from(
      this.client
        .from('conversations')
        .select('*')
        .eq('user_id', userId)
        .order('updated_at', { ascending: false })
        .then(({ data, error }) => {
          if (error) throw error;
          return (data as Conversation[]) ?? [];
        })
    );
  }

  createConversation(userId: string, title: string, area: string): Observable<Conversation> {
    return from(
      this.client
        .from('conversations')
        .insert({ user_id: userId, title, area, message_count: 0 })
        .select()
        .single()
        .then(({ data, error }) => {
          if (error) throw error;
          return data as Conversation;
        })
    );
  }

  getMessages(conversationId: string): Observable<ConversationMessage[]> {
    return from(
      this.client
        .from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true })
        .then(({ data, error }) => {
          if (error) throw error;
          return (data as ConversationMessage[]) ?? [];
        })
    );
  }

  saveMessage(msg: Omit<ConversationMessage, 'id' | 'created_at'>): Observable<ConversationMessage> {
    return from(
      this.client
        .from('messages')
        .insert(msg)
        .select()
        .single()
        .then(({ data, error }) => {
          if (error) throw error;
          return data as ConversationMessage;
        })
    );
  }

  // ─── DOCUMENTOS DEL CASO ──────────────────────────────────────────────────

  uploadCaseDocument(file: File, caseId: string, userId: string): Observable<string> {
    const path = `${userId}/cases/${caseId}/${file.name}`;
    return from(
      this.client.storage
        .from('case-documents')
        .upload(path, file, { upsert: true })
        .then(({ data, error }) => {
          if (error) throw error;
          return data.path;
        })
    );
  }
}
'@

    Set-Content -Path "$ProjectRoot/frontend/src/app/core/services/supabase.service.ts" -Value $content
    Write-OK "Supabase Service generado"
}

function New-ChatComponent {
    Write-Step "Generando componente Chat principal..."

    # Component TypeScript
    $componentTs = @'
// src/app/features/chat/chat.component.ts
// Componente principal de chat jurídico para JURIS-FREE Bolivia

import {
  Component,
  OnInit,
  OnDestroy,
  ViewChild,
  ElementRef,
  inject,
  signal,
  computed
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';
import { FormControl } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { LlmProxyService, LlmMessage } from '../../core/services/llm-proxy.service';
import { SupabaseService } from '../../core/services/supabase.service';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatTooltipModule } from '@angular/material/tooltip';

export type LegalArea = 'civil' | 'penal' | 'laboral' | 'constitucional' | 'administrativo' | 'comercial' | 'auto';

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
  provider?: string;
  tokensUsed?: number;
  sources?: LegalSource[];
  isStreaming?: boolean;
}

interface LegalSource {
  title: string;
  type: string;
  relevance: number;
  excerpt: string;
}

// Prompt de sistema para el abogado boliviano
const SYSTEM_PROMPT = `Eres JURIS-FREE, un asistente jurídico especializado en el derecho boliviano.

CONTEXTO:
- Sistema jurídico: Bolivia (Estado Plurinacional)
- Constitución: CPE 2009
- Códigos aplicables: Civil (Ley 12760), Penal (Ley 1768), Familiar (Ley 996), Tributario, Laboral, etc.
- Jurisprudencia: Tribunal Constitucional Plurinacional (TCP), Tribunal Supremo de Justicia (TSJ)

INSTRUCCIONES:
1. Responde SIEMPRE citando el artículo exacto y la norma específica de Bolivia
2. Si hay jurisprudencia del TCP o TSJ relevante, menciónala con el número de sentencia
3. Distingue claramente entre norma vigente y norma derogada
4. Si la consulta requiere criterio profesional, da la base legal pero recomienda consultar a un abogado habilitado
5. Estructura la respuesta con: Base Legal → Análisis → Consecuencias Jurídicas → Recomendación
6. NUNCA inventes artículos o sentencias. Si no tienes la información exacta, dilo claramente.
7. Usa terminología jurídica precisa pero explica los tecnicismos cuando sea necesario

FORMATO: Usa markdown para estructura. Citas legales en **negritas**. Artículos específicos en \`código\`.`;

@Component({
  selector: 'app-chat',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    ReactiveFormsModule,
    MatIconModule,
    MatProgressSpinnerModule,
    MatTooltipModule
  ],
  templateUrl: './chat.component.html',
  styleUrls: ['./chat.component.scss']
})
export class ChatComponent implements OnInit, OnDestroy {
  @ViewChild('messagesContainer') messagesContainer!: ElementRef;
  @ViewChild('inputField') inputField!: ElementRef;

  private llm = inject(LlmProxyService);
  private supabase = inject(SupabaseService);
  private destroy$ = new Subject<void>();

  // Signals para estado reactivo
  messages = signal<ChatMessage[]>([]);
  isLoading = signal(false);
  selectedArea = signal<LegalArea>('auto');
  currentProvider = signal<string>('');
  inputControl = new FormControl('', { nonNullable: true });

  conversationHistory: LlmMessage[] = [];
  currentConversationId: string | null = null;

  readonly areas: { value: LegalArea; label: string; icon: string }[] = [
    { value: 'auto',           label: 'Detección automática', icon: 'auto_fix_high' },
    { value: 'civil',          label: 'Derecho Civil',        icon: 'gavel' },
    { value: 'penal',          label: 'Derecho Penal',        icon: 'security' },
    { value: 'laboral',        label: 'Derecho Laboral',      icon: 'work' },
    { value: 'constitucional', label: 'Derecho Constitucional', icon: 'account_balance' },
    { value: 'administrativo', label: 'Derecho Administrativo', icon: 'business' },
    { value: 'comercial',      label: 'Derecho Comercial',    icon: 'store' }
  ];

  readonly usageStats = computed(() => this.llm.getUsageStats());

  // Mensaje de bienvenida
  readonly welcomeMessage: ChatMessage = {
    id: 'welcome',
    role: 'assistant',
    content: `## ¡Bienvenido a JURIS-FREE Bolivia! ⚖️

Soy tu asistente jurídico especializado en el **derecho boliviano**. Puedo ayudarte con:

- 📋 **Consultas legales** sobre normativa boliviana vigente
- 🔍 **Búsqueda de jurisprudencia** del TCP y TSJ
- 📝 **Análisis de contratos** y documentos legales
- ⚖️ **Procedimientos judiciales** y plazos
- 🏛️ **Derecho Constitucional** y derechos fundamentales

**¿Cómo usarme?**
Escribe tu consulta jurídica en lenguaje natural. Por ejemplo:
*"¿Cuáles son los plazos para interponer un recurso de apelación en materia civil?"*

> 💡 Selecciona el área de derecho para obtener respuestas más precisas.`,
    timestamp: new Date(),
    provider: 'sistema'
  };

  ngOnInit(): void {
    this.messages.set([this.welcomeMessage]);
    this.loadConversationFromStorage();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  async sendMessage(): Promise<void> {
    const text = this.inputControl.value.trim();
    if (!text || this.isLoading()) return;

    const userMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'user',
      content: text,
      timestamp: new Date()
    };

    this.messages.update(msgs => [...msgs, userMsg]);
    this.inputControl.reset();
    this.isLoading.set(true);
    this.scrollToBottom();

    // Agregar a historial de conversación
    this.conversationHistory.push({ role: 'user', content: text });

    // Placeholder de respuesta mientras carga
    const assistantMsgId = crypto.randomUUID();
    const assistantMsg: ChatMessage = {
      id: assistantMsgId,
      role: 'assistant',
      content: '',
      timestamp: new Date(),
      isStreaming: true
    };
    this.messages.update(msgs => [...msgs, assistantMsg]);

    try {
      this.llm.chat(
        this.conversationHistory,
        SYSTEM_PROMPT,
        this.selectedArea() !== 'auto' ? undefined : undefined
      ).pipe(takeUntil(this.destroy$))
       .subscribe({
          next: (response) => {
            this.conversationHistory.push({
              role: 'assistant',
              content: response.content
            });

            this.messages.update(msgs =>
              msgs.map(m => m.id === assistantMsgId
                ? {
                    ...m,
                    content: response.content,
                    provider: response.provider,
                    tokensUsed: response.tokensUsed,
                    isStreaming: false
                  }
                : m
              )
            );

            this.currentProvider.set(response.provider);
            this.isLoading.set(false);
            this.saveConversationToStorage();
            this.scrollToBottom();
          },
          error: (err) => {
            this.messages.update(msgs =>
              msgs.map(m => m.id === assistantMsgId
                ? { ...m, content: `❌ Error: ${err.message}`, isStreaming: false }
                : m
              )
            );
            this.isLoading.set(false);
          }
        });
    } catch (err: unknown) {
      this.isLoading.set(false);
      console.error('[Chat] Error:', err);
    }
  }

  onKeydown(event: KeyboardEvent): void {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      this.sendMessage();
    }
  }

  selectArea(area: LegalArea): void {
    this.selectedArea.set(area);
  }

  clearConversation(): void {
    this.conversationHistory = [];
    this.messages.set([this.welcomeMessage]);
    localStorage.removeItem('juris_conversation');
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      const el = this.messagesContainer?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    }, 100);
  }

  private saveConversationToStorage(): void {
    localStorage.setItem('juris_conversation',
      JSON.stringify(this.conversationHistory.slice(-20)) // Últimos 20 mensajes
    );
  }

  private loadConversationFromStorage(): void {
    try {
      const stored = localStorage.getItem('juris_conversation');
      if (stored) {
        this.conversationHistory = JSON.parse(stored);
      }
    } catch {
      this.conversationHistory = [];
    }
  }
}
'@

    # Component HTML
    $componentHtml = @'
<!-- src/app/features/chat/chat.component.html -->
<div class="chat-container">

  <!-- Header -->
  <header class="chat-header">
    <div class="header-brand">
      <span class="brand-icon">⚖️</span>
      <span class="brand-name">JURIS-FREE <span class="brand-country">Bolivia</span></span>
    </div>
    <div class="header-actions">
      @if (currentProvider()) {
        <span class="provider-badge">{{ currentProvider() }}</span>
      }
      <button class="btn-icon" (click)="clearConversation()" matTooltip="Nueva conversación">
        <mat-icon>add_comment</mat-icon>
      </button>
    </div>
  </header>

  <!-- Selector de área legal -->
  <div class="area-selector">
    @for (area of areas; track area.value) {
      <button
        class="area-chip"
        [class.active]="selectedArea() === area.value"
        (click)="selectArea(area.value)">
        <mat-icon>{{ area.icon }}</mat-icon>
        <span>{{ area.label }}</span>
      </button>
    }
  </div>

  <!-- Mensajes -->
  <div class="messages-container" #messagesContainer>
    @for (message of messages(); track message.id) {
      <div class="message" [class.user]="message.role === 'user'" [class.assistant]="message.role === 'assistant'">

        @if (message.role === 'assistant') {
          <div class="message-avatar">⚖️</div>
        }

        <div class="message-bubble">
          @if (message.isStreaming) {
            <div class="typing-indicator">
              <span></span><span></span><span></span>
            </div>
          } @else {
            <div class="message-content" [innerHTML]="message.content"></div>
          }

          <div class="message-meta">
            <span class="message-time">{{ message.timestamp | date:'HH:mm' }}</span>
            @if (message.provider && message.provider !== 'sistema') {
              <span class="message-provider">{{ message.provider }}</span>
            }
            @if (message.tokensUsed) {
              <span class="message-tokens">{{ message.tokensUsed }} tokens</span>
            }
          </div>
        </div>

        @if (message.role === 'user') {
          <div class="message-avatar user-avatar">
            <mat-icon>person</mat-icon>
          </div>
        }
      </div>
    }
  </div>

  <!-- Input -->
  <div class="input-container">
    <textarea
      #inputField
      class="message-input"
      [formControl]="inputControl"
      placeholder="Consulta sobre derecho boliviano... (Enter para enviar, Shift+Enter para nueva línea)"
      rows="2"
      (keydown)="onKeydown($event)"
      [disabled]="isLoading()">
    </textarea>

    <button
      class="send-button"
      (click)="sendMessage()"
      [disabled]="isLoading() || !inputControl.value.trim()"
      matTooltip="Enviar consulta">
      @if (isLoading()) {
        <mat-progress-spinner diameter="20" mode="indeterminate"></mat-progress-spinner>
      } @else {
        <mat-icon>send</mat-icon>
      }
    </button>
  </div>

  <!-- Footer info -->
  <div class="chat-footer">
    <span>🇧🇴 Derecho boliviano · CPE 2009 · TCP · TSJ · Gaceta Oficial</span>
    <span>Gratuito para siempre · Open Source</span>
  </div>

</div>
'@

    # Component SCSS
    $componentScss = @'
/* src/app/features/chat/chat.component.scss */
/* JURIS-FREE Bolivia — Diseño legal, profesional, accesible */

:host {
  display: block;
  height: 100vh;
  font-family: 'Crimson Pro', 'Georgia', serif;
  --color-primary: #1a3a5c;
  --color-accent: #c4922a;
  --color-bg: #f8f6f1;
  --color-surface: #ffffff;
  --color-border: #e0d8c8;
  --color-text: #2c2416;
  --color-muted: #7a6e5e;
  --radius: 12px;
}

.chat-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: var(--color-bg);
  max-width: 900px;
  margin: 0 auto;
}

/* ── Header ─────────────────────────────────── */
.chat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 20px;
  background: var(--color-primary);
  color: white;
  border-bottom: 3px solid var(--color-accent);

  .header-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 1.2rem;
    font-weight: 700;
    letter-spacing: 0.05em;
  }

  .brand-icon { font-size: 1.5rem; }

  .brand-country {
    color: var(--color-accent);
    font-style: italic;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .provider-badge {
    background: rgba(196, 146, 42, 0.25);
    border: 1px solid var(--color-accent);
    color: #ffd98e;
    font-size: 0.7rem;
    padding: 3px 10px;
    border-radius: 20px;
    font-family: 'JetBrains Mono', monospace;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .btn-icon {
    background: none;
    border: none;
    color: rgba(255,255,255,0.7);
    cursor: pointer;
    padding: 6px;
    border-radius: 8px;
    transition: all 0.2s;

    &:hover {
      background: rgba(255,255,255,0.1);
      color: white;
    }
  }
}

/* ── Selector de área ────────────────────────── */
.area-selector {
  display: flex;
  gap: 6px;
  padding: 10px 16px;
  background: var(--color-surface);
  border-bottom: 1px solid var(--color-border);
  overflow-x: auto;
  scrollbar-width: none;

  &::-webkit-scrollbar { display: none; }
}

.area-chip {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border: 1px solid var(--color-border);
  background: white;
  border-radius: 20px;
  cursor: pointer;
  font-size: 0.78rem;
  white-space: nowrap;
  transition: all 0.2s;
  color: var(--color-muted);

  mat-icon { font-size: 14px; width: 14px; height: 14px; }

  &:hover {
    border-color: var(--color-primary);
    color: var(--color-primary);
  }

  &.active {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: white;
  }
}

/* ── Mensajes ────────────────────────────────── */
.messages-container {
  flex: 1;
  overflow-y: auto;
  padding: 20px 16px;
  display: flex;
  flex-direction: column;
  gap: 16px;
  scroll-behavior: smooth;
}

.message {
  display: flex;
  gap: 10px;
  align-items: flex-start;

  &.user {
    flex-direction: row-reverse;

    .message-bubble {
      background: var(--color-primary);
      color: white;
      border-radius: var(--radius) var(--radius) 4px var(--radius);

      .message-meta { color: rgba(255,255,255,0.55); }
    }
  }

  &.assistant .message-bubble {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius) var(--radius) var(--radius) 4px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
  }
}

.message-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: var(--color-accent);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.1rem;
  flex-shrink: 0;

  &.user-avatar {
    background: var(--color-primary);
    color: white;

    mat-icon { font-size: 18px; }
  }
}

.message-bubble {
  max-width: 75%;
  padding: 12px 16px;
}

.message-content {
  font-size: 0.92rem;
  line-height: 1.65;
  color: var(--color-text);

  ::ng-deep {
    strong { color: var(--color-primary); }
    code { background: rgba(26,58,92,0.07); padding: 1px 5px; border-radius: 4px; font-size: 0.85em; }
    blockquote { border-left: 3px solid var(--color-accent); padding-left: 12px; margin: 8px 0; color: var(--color-muted); }
    h2, h3 { color: var(--color-primary); margin: 12px 0 6px; font-size: 1em; }
    ul, ol { padding-left: 18px; }
    p { margin: 6px 0; }
  }
}

.message-meta {
  display: flex;
  gap: 8px;
  margin-top: 6px;
  font-size: 0.7rem;
  color: var(--color-muted);
  font-family: monospace;
}

/* ── Indicador de escritura ──────────────────── */
.typing-indicator {
  display: flex;
  gap: 4px;
  padding: 4px 0;

  span {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--color-muted);
    animation: typing 1.2s infinite;

    &:nth-child(2) { animation-delay: 0.2s; }
    &:nth-child(3) { animation-delay: 0.4s; }
  }
}

@keyframes typing {
  0%, 80%, 100% { transform: scale(0.7); opacity: 0.4; }
  40%           { transform: scale(1);   opacity: 1;   }
}

/* ── Input ───────────────────────────────────── */
.input-container {
  display: flex;
  gap: 10px;
  padding: 14px 16px;
  background: var(--color-surface);
  border-top: 1px solid var(--color-border);
}

.message-input {
  flex: 1;
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
  padding: 10px 14px;
  font-size: 0.9rem;
  font-family: inherit;
  resize: none;
  background: var(--color-bg);
  color: var(--color-text);
  transition: border-color 0.2s;

  &:focus {
    outline: none;
    border-color: var(--color-primary);
    background: white;
  }

  &:disabled { opacity: 0.6; cursor: not-allowed; }
}

.send-button {
  width: 46px;
  height: 46px;
  border-radius: 50%;
  border: none;
  background: var(--color-primary);
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
  flex-shrink: 0;

  &:hover:not(:disabled) { background: #0f2440; transform: scale(1.05); }
  &:disabled { opacity: 0.4; cursor: not-allowed; }
}

/* ── Footer ──────────────────────────────────── */
.chat-footer {
  display: flex;
  justify-content: space-between;
  padding: 6px 16px;
  font-size: 0.68rem;
  color: var(--color-muted);
  background: var(--color-bg);
  border-top: 1px solid var(--color-border);
}
'@

    Set-Content -Path "$ProjectRoot/frontend/src/app/features/chat/chat.component.ts"    -Value $componentTs
    Set-Content -Path "$ProjectRoot/frontend/src/app/features/chat/chat.component.html"  -Value $componentHtml
    Set-Content -Path "$ProjectRoot/frontend/src/app/features/chat/chat.component.scss"  -Value $componentScss
    Write-OK "Chat Component generado (TS + HTML + SCSS)"
}

function New-AppRouting {
    Write-Step "Generando App Routing..."

    $content = @'
// src/app/app.routes.ts
import { Routes } from '@angular/router';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  { path: '', redirectTo: '/chat', pathMatch: 'full' },
  {
    path: 'chat',
    loadComponent: () => import('./features/chat/chat.component').then(m => m.ChatComponent)
  },
  {
    path: 'library',
    loadComponent: () => import('./features/library/library.component').then(m => m.LibraryComponent),
    canActivate: [authGuard]
  },
  {
    path: 'cases',
    loadComponent: () => import('./features/cases/cases.component').then(m => m.CasesComponent),
    canActivate: [authGuard]
  },
  {
    path: 'settings',
    loadComponent: () => import('./features/settings/settings.component').then(m => m.SettingsComponent),
    canActivate: [authGuard]
  },
  {
    path: 'auth/callback',
    loadComponent: () => import('./core/auth-callback/auth-callback.component').then(m => m.AuthCallbackComponent)
  },
  { path: '**', redirectTo: '/chat' }
];
'@

    Set-Content -Path "$ProjectRoot/frontend/src/app/app.routes.ts" -Value $content

    # Auth Guard
    $guard = @'
// src/app/core/guards/auth.guard.ts
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SupabaseService } from '../services/supabase.service';
import { map, take } from 'rxjs/operators';

export const authGuard: CanActivateFn = () => {
  const supabase = inject(SupabaseService);
  const router = inject(Router);

  return supabase.isAuthenticated$.pipe(
    take(1),
    map(isAuth => isAuth ? true : router.createUrlTree(['/chat']))
  );
};
'@

    Set-Content -Path "$ProjectRoot/frontend/src/app/core/guards/auth.guard.ts" -Value $guard
    Write-OK "Routing + Guards generados"
}

function New-EnvironmentFiles {
    Write-Step "Generando archivos de entorno..."

    $envDev = @'
// src/environments/environment.ts
export const environment = {
  production: false,
  apiUrl: 'http://localhost:8000',
  supabaseUrl: 'YOUR_SUPABASE_URL',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
  cloudflareWorkerUrl: 'https://juris-free.YOUR_SUBDOMAIN.workers.dev'
};
'@

    $envProd = @'
// src/environments/environment.production.ts
export const environment = {
  production: true,
  apiUrl: 'https://YOUR_ORACLE_VM_IP',
  supabaseUrl: 'YOUR_SUPABASE_URL',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
  cloudflareWorkerUrl: 'https://juris-free.YOUR_SUBDOMAIN.workers.dev'
};
'@

    New-Item -Path "$ProjectRoot/frontend/src/environments" -ItemType Directory -Force | Out-Null
    Set-Content -Path "$ProjectRoot/frontend/src/environments/environment.ts" -Value $envDev
    Set-Content -Path "$ProjectRoot/frontend/src/environments/environment.production.ts" -Value $envProd
    Write-OK "Environments generados"
}

function New-TailwindConfig {
    Write-Step "Configurando Tailwind CSS..."

    $tailwindConfig = @'
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{html,ts,scss}"
  ],
  theme: {
    extend: {
      colors: {
        juris: {
          primary:   '#1a3a5c',
          accent:    '#c4922a',
          bg:        '#f8f6f1',
          surface:   '#ffffff',
          border:    '#e0d8c8',
          text:      '#2c2416',
          muted:     '#7a6e5e'
        }
      },
      fontFamily: {
        serif: ['Crimson Pro', 'Georgia', 'serif'],
        mono:  ['JetBrains Mono', 'Consolas', 'monospace']
      }
    }
  },
  plugins: []
}
'@

    Set-Content -Path "$ProjectRoot/frontend/tailwind.config.js" -Value $tailwindConfig
    Write-OK "Tailwind configurado"
}

function New-AngularMaterial {
    Write-Step "Configurando Angular Material (tema legal)..."

    $themeScss = @'
// src/styles.scss — Tema global JURIS-FREE Bolivia
@use '@angular/material' as mat;

// Importar tipografía legal
@import url('https://fonts.googleapis.com/css2?family=Crimson+Pro:ital,wght@0,400;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;500&display=swap');

@include mat.core();

$juris-primary: mat.define-palette(mat.$blue-palette, 900, 700, 900);
$juris-accent:  mat.define-palette(mat.$amber-palette, 700, 500, 900);
$juris-warn:    mat.define-palette(mat.$red-palette);

$juris-theme: mat.define-light-theme((
  color: (
    primary: $juris-primary,
    accent:  $juris-accent,
    warn:    $juris-warn
  ),
  typography: mat.define-typography-config(
    $font-family: "'Crimson Pro', Georgia, serif"
  )
));

@include mat.all-component-themes($juris-theme);

* { box-sizing: border-box; margin: 0; padding: 0; }

html, body {
  height: 100%;
  overflow: hidden;
  font-family: 'Crimson Pro', Georgia, serif;
  background: #f8f6f1;
}

::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #d4c9b5; border-radius: 3px; }
'@

    Set-Content -Path "$ProjectRoot/frontend/src/styles.scss" -Value $themeScss
    Write-OK "Angular Material + estilos globales configurados"
}

# ─── 6. CLOUDFLARE WORKERS (AGENTES L-MARS EN TYPESCRIPT) ────────────────────
function New-CloudflareWorkers {
    Write-Header "Configurando Cloudflare Workers (Agentes L-MARS)"

    # wrangler.toml para el orquestador
    $wranglerToml = @'
# workers/orchestrator/wrangler.toml
name = "juris-free-orchestrator"
main = "src/index.ts"
compatibility_date = "2024-11-01"
compatibility_flags = ["nodejs_compat"]

[vars]
ENVIRONMENT = "production"
BACKEND_URL = "https://YOUR_ORACLE_VM_IP"

[[services]]
binding = "AGENT_CIVIL"
service = "juris-agent-civil"

[[services]]
binding = "AGENT_PENAL"
service = "juris-agent-penal"

[[services]]
binding = "AGENT_LABORAL"
service = "juris-agent-laboral"

[[services]]
binding = "AGENT_JUDGE"
service = "juris-agent-judge"

[ai]
binding = "AI"
'@

    # Orquestador TypeScript — Agente coordinador
    $orchestratorTs = @'
// workers/orchestrator/src/index.ts
// Agente Orquestador JURIS-FREE — Implementación L-MARS para Bolivia
// Descompone consultas legales y coordina agentes especializados en paralelo

import { Env, LegalQuery, AgentResponse, OrchestratorResult } from './types';
import { detectLegalAreas } from './area-detector';
import { mergeAgentResponses } from './response-merger';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return corsResponse('', 204);
    }

    if (request.method !== 'POST') {
      return corsResponse(JSON.stringify({ error: 'Method not allowed' }), 405);
    }

    try {
      const body = await request.json() as LegalQuery;
      const result = await orchestrate(body, env);
      return corsResponse(JSON.stringify(result), 200);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return corsResponse(JSON.stringify({ error: message }), 500);
    }
  }
};

async function orchestrate(query: LegalQuery, env: Env): Promise<OrchestratorResult> {
  const startTime = Date.now();

  // 1. DETECCIÓN DE ÁREAS LEGALES (modelo pequeño, <50ms)
  const areas = await detectLegalAreas(query.text, env);

  // 2. BÚSQUEDA PARALELA en agentes especializados
  const agentCalls = buildAgentCalls(query, areas, env);
  const agentResults = await Promise.allSettled(agentCalls);

  const responses: AgentResponse[] = agentResults
    .filter((r): r is PromiseFulfilledResult<AgentResponse> => r.status === 'fulfilled')
    .map(r => r.value);

  // 3. VERIFICACIÓN JURÍDICA (Agente Juez)
  const verifiedResponse = await runJudgeAgent(query, responses, env);

  // 4. RESPUESTA FINAL
  return {
    answer: verifiedResponse.content,
    areasDetected: areas,
    agentsUsed: responses.map(r => r.agentName),
    sources: verifiedResponse.sources,
    confidence: verifiedResponse.confidence,
    processingMs: Date.now() - startTime
  };
}

function buildAgentCalls(
  query: LegalQuery,
  areas: string[],
  env: Env
): Promise<AgentResponse>[] {
  const calls: Promise<AgentResponse>[] = [];
  const agentPayload = JSON.stringify({ text: query.text, context: query.context });

  if (areas.includes('civil') || areas.includes('auto')) {
    calls.push(callAgent(env.AGENT_CIVIL, agentPayload, 'civil'));
  }
  if (areas.includes('penal')) {
    calls.push(callAgent(env.AGENT_PENAL, agentPayload, 'penal'));
  }
  if (areas.includes('laboral')) {
    calls.push(callAgent(env.AGENT_LABORAL, agentPayload, 'laboral'));
  }
  if (areas.includes('constitucional')) {
    // Constitucional siempre se invoca para preguntas complejas
    calls.push(callAgent(env.AGENT_CIVIL, agentPayload, 'constitucional'));
  }

  // Mínimo 1 agente siempre
  if (calls.length === 0) {
    calls.push(callAgent(env.AGENT_CIVIL, agentPayload, 'general'));
  }

  return calls;
}

async function callAgent(
  service: Fetcher,
  payload: string,
  agentName: string
): Promise<AgentResponse> {
  const response = await service.fetch('https://worker/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: payload
  });

  const data = await response.json() as AgentResponse;
  return { ...data, agentName };
}

async function runJudgeAgent(
  query: LegalQuery,
  responses: AgentResponse[],
  env: Env
): Promise<{ content: string; sources: string[]; confidence: number }> {
  // Usar Workers AI (Llama 3.2 3B) para verificación — gratis hasta 10k req/día
  const judgePrompt = buildJudgePrompt(query.text, responses);

  const aiResponse = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
    prompt: judgePrompt,
    max_tokens: 150
  });

  // Si el juez detecta contradicciones, marcar confianza baja
  const hasContradiction = aiResponse.response?.toLowerCase().includes('contradicción') ||
                           aiResponse.response?.toLowerCase().includes('inconsistencia');

  // Sintetizar respuesta del agente con más información
  const bestResponse = responses.reduce((best, curr) =>
    (curr.content?.length ?? 0) > (best.content?.length ?? 0) ? curr : best
  , responses[0]);

  return {
    content: bestResponse?.content ?? 'No se pudo generar una respuesta.',
    sources: responses.flatMap(r => r.sources ?? []),
    confidence: hasContradiction ? 0.6 : 0.92
  };
}

function buildJudgePrompt(query: string, responses: AgentResponse[]): string {
  const responseSummary = responses
    .map(r => `[${r.agentName}]: ${r.content?.substring(0, 200)}...`)
    .join('\n');

  return `Eres un juez jurídico. Analiza si estas respuestas sobre derecho boliviano son consistentes entre sí.

Consulta: "${query}"

Respuestas de los agentes:
${responseSummary}

¿Hay contradicciones o inconsistencias? Responde en UNA oración.`;
}

function corsResponse(body: string, status: number): Response {
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
  });
}
'@

    # Types compartidos
    $typesTs = @'
// workers/orchestrator/src/types.ts
export interface Env {
  AGENT_CIVIL:      Fetcher;
  AGENT_PENAL:      Fetcher;
  AGENT_LABORAL:    Fetcher;
  AGENT_JUDGE:      Fetcher;
  AI:               Ai;
  BACKEND_URL:      string;
  ENVIRONMENT:      string;
}

export interface LegalQuery {
  text:       string;
  context?:   string;
  area?:      string;
  userId?:    string;
}

export interface AgentResponse {
  agentName:   string;
  content:     string;
  sources?:    string[];
  confidence?: number;
  area?:       string;
}

export interface OrchestratorResult {
  answer:        string;
  areasDetected: string[];
  agentsUsed:    string[];
  sources:       string[];
  confidence:    number;
  processingMs:  number;
}
'@

    New-Item -Path "$ProjectRoot/workers/orchestrator/src" -ItemType Directory -Force | Out-Null
    Set-Content -Path "$ProjectRoot/workers/orchestrator/wrangler.toml"    -Value $wranglerToml
    Set-Content -Path "$ProjectRoot/workers/orchestrator/src/index.ts"     -Value $orchestratorTs
    Set-Content -Path "$ProjectRoot/workers/orchestrator/src/types.ts"     -Value $typesTs

    Write-OK "Cloudflare Workers (Orquestador L-MARS) generado"
}

# ─── 7. BACKEND FASTAPI (ORACLE VM) ──────────────────────────────────────────
function New-FastAPIBackend {
    Write-Header "Configurando backend FastAPI (Oracle VM)"

    $mainPy = @'
# backend/api/main.py
# JURIS-FREE Bolivia — Backend FastAPI
# Corre en Oracle Cloud Always Free (4 ARM cores, 24GB RAM)

from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from contextlib import asynccontextmanager
import asyncio
import logging
import os

from .routes import chat, llm, embeddings, ingest
from .models.schemas import HealthResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 JURIS-FREE Bolivia API iniciando...")
    yield
    logger.info("👋 JURIS-FREE Bolivia API apagando...")

app = FastAPI(
    title="JURIS-FREE Bolivia API",
    description="Sistema jurídico inteligente para Bolivia — Open Source",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # En producción: especificar dominio Vercel
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chat.router,       prefix="/api/v1/chat",       tags=["Chat"])
app.include_router(llm.router,        prefix="/api/v1/llm",        tags=["LLM"])
app.include_router(embeddings.router, prefix="/api/v1/embeddings", tags=["Embeddings"])
app.include_router(ingest.router,     prefix="/api/v1/ingest",     tags=["Ingesta"])

@app.get("/health", response_model=HealthResponse)
async def health():
    return {"status": "ok", "service": "juris-free-bolivia", "version": "1.0.0"}

@app.get("/")
async def root():
    return {"message": "JURIS-FREE Bolivia API — Sistema Jurídico Open Source"}
'@

    # LLM Router con proxy multi-proveedor
    $llmRouterPy = @'
# backend/api/routes/llm.py
# Proxy LLM multi-proveedor: Gemini → Groq → Cerebras → OpenRouter → SambaNova

import httpx
import os
import time
import asyncio
import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List

logger = logging.getLogger(__name__)
router = APIRouter()

class Message(BaseModel):
    role: str   # 'user' | 'assistant' | 'system'
    content: str

class ChatRequest(BaseModel):
    provider:  Optional[str] = None
    model:     Optional[str] = None
    messages:  List[Message]
    system:    Optional[str] = None
    max_tokens: int = 2048

class ChatResponse(BaseModel):
    content:     str
    provider:    str
    model:       str
    tokens_used: int
    latency_ms:  int

# Configuración de proveedores (mayo 2026)
PROVIDERS = [
    {
        "name": "gemini",
        "base_url": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
        "api_key_env": "GEMINI_API_KEY",
        "model": "gemini-2.5-flash",
        "format": "gemini"
    },
    {
        "name": "groq",
        "base_url": "https://api.groq.com/openai/v1/chat/completions",
        "api_key_env": "GROQ_API_KEY",
        "model": "llama-3.3-70b-versatile",
        "format": "openai"
    },
    {
        "name": "cerebras",
        "base_url": "https://api.cerebras.ai/v1/chat/completions",
        "api_key_env": "CEREBRAS_API_KEY",
        "model": "llama3.3-70b",
        "format": "openai"
    },
    {
        "name": "openrouter",
        "base_url": "https://openrouter.ai/api/v1/chat/completions",
        "api_key_env": "OPENROUTER_API_KEY",
        "model": "qwen/qwen-2.5-72b-instruct:free",
        "format": "openai"
    },
    {
        "name": "sambanova",
        "base_url": "https://api.sambanova.ai/v1/chat/completions",
        "api_key_env": "SAMBANOVA_API_KEY",
        "model": "Meta-Llama-3.3-70B-Instruct",
        "format": "openai"
    }
]

# Rate limit tracking (en memoria — resetea al reiniciar VM)
_rate_limited_until: dict = {}

async def call_openai_compatible(
    provider: dict,
    messages: List[Message],
    system: Optional[str],
    max_tokens: int
) -> tuple[str, int]:
    """Llama a cualquier proveedor con formato OpenAI."""
    api_key = os.getenv(provider["api_key_env"])
    if not api_key:
        raise ValueError(f"API key no configurada: {provider['api_key_env']}")

    all_messages = []
    if system:
        all_messages.append({"role": "system", "content": system})
    all_messages.extend([{"role": m.role, "content": m.content} for m in messages])

    payload = {
        "model": provider["model"],
        "messages": all_messages,
        "max_tokens": max_tokens,
        "temperature": 0.3
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            provider["base_url"],
            json=payload,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
        )

        if response.status_code == 429:
            raise httpx.HTTPStatusError("Rate limit", request=response.request, response=response)

        response.raise_for_status()
        data = response.json()

        content = data["choices"][0]["message"]["content"]
        tokens = data.get("usage", {}).get("total_tokens", len(content.split()) * 2)
        return content, tokens

async def call_gemini(
    provider: dict,
    messages: List[Message],
    system: Optional[str],
    max_tokens: int
) -> tuple[str, int]:
    """Llama a Gemini con su formato específico."""
    api_key = os.getenv(provider["api_key_env"])
    if not api_key:
        raise ValueError("GEMINI_API_KEY no configurada")

    # Convertir formato
    contents = []
    if system:
        contents.append({"role": "user", "parts": [{"text": f"[Sistema]: {system}"}]})
        contents.append({"role": "model", "parts": [{"text": "Entendido."}]})

    for msg in messages:
        role = "model" if msg.role == "assistant" else "user"
        contents.append({"role": role, "parts": [{"text": msg.content}]})

    payload = {
        "contents": contents,
        "generationConfig": {"maxOutputTokens": max_tokens, "temperature": 0.3}
    }

    url = f"{provider['base_url']}?key={api_key}"
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, json=payload)

        if response.status_code == 429:
            raise httpx.HTTPStatusError("Rate limit", request=response.request, response=response)

        response.raise_for_status()
        data = response.json()

        content = data["candidates"][0]["content"]["parts"][0]["text"]
        tokens = data.get("usageMetadata", {}).get("totalTokenCount", 0)
        return content, tokens

@router.post("/chat", response_model=ChatResponse)
async def chat_completion(request: ChatRequest):
    """
    Proxy LLM con fallover automático entre proveedores gratuitos.
    Orden: Gemini → Groq → Cerebras → OpenRouter → SambaNova
    """
    providers_to_try = PROVIDERS.copy()

    # Si el usuario pidió un proveedor específico, priorizar
    if request.provider:
        pref = next((p for p in providers_to_try if p["name"] == request.provider), None)
        if pref:
            providers_to_try = [pref] + [p for p in providers_to_try if p["name"] != request.provider]

    last_error = None
    for provider in providers_to_try:
        # Verificar si está en rate limit
        if provider["name"] in _rate_limited_until:
            if time.time() < _rate_limited_until[provider["name"]]:
                logger.info(f"[LLM] {provider['name']} en rate limit, saltando...")
                continue
            else:
                del _rate_limited_until[provider["name"]]

        try:
            start = time.time()
            logger.info(f"[LLM] Intentando {provider['name']}...")

            if provider["format"] == "gemini":
                content, tokens = await call_gemini(provider, request.messages, request.system, request.max_tokens)
            else:
                content, tokens = await call_openai_compatible(provider, request.messages, request.system, request.max_tokens)

            latency = int((time.time() - start) * 1000)
            logger.info(f"[LLM] ✓ {provider['name']} respondió en {latency}ms ({tokens} tokens)")

            return ChatResponse(
                content=content,
                provider=provider["name"],
                model=provider["model"],
                tokens_used=tokens,
                latency_ms=latency
            )

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                _rate_limited_until[provider["name"]] = time.time() + 900  # 15 min
                logger.warning(f"[LLM] {provider['name']} rate limited, marcado por 15min")
            else:
                logger.error(f"[LLM] {provider['name']} HTTP error: {e.response.status_code}")
            last_error = str(e)
            continue
        except Exception as e:
            logger.error(f"[LLM] {provider['name']} error: {e}")
            last_error = str(e)
            continue

    raise HTTPException(
        status_code=503,
        detail=f"Todos los proveedores LLM fallaron. Último error: {last_error}"
    )
'@

    # requirements.txt
    $requirements = @'
fastapi==0.115.0
uvicorn[standard]==0.32.0
httpx==0.27.2
pydantic==2.9.2
supabase==2.9.1
sentence-transformers==3.2.1
numpy==1.26.4
python-dotenv==1.0.1
asyncio==3.4.3
'@

    New-Item -Path "$ProjectRoot/backend/api/routes" -ItemType Directory -Force | Out-Null
    Set-Content -Path "$ProjectRoot/backend/api/main.py"               -Value $mainPy
    Set-Content -Path "$ProjectRoot/backend/api/routes/llm.py"         -Value $llmRouterPy
    Set-Content -Path "$ProjectRoot/backend/requirements.txt"           -Value $requirements

    Write-OK "Backend FastAPI generado"
}

# ─── 8. GITHUB ACTIONS (KEEP-ALIVE + CI/CD) ───────────────────────────────────
function New-GitHubActions {
    Write-Header "Configurando GitHub Actions"

    New-Item -Path "$ProjectRoot/infra/github-actions" -ItemType Directory -Force | Out-Null

    # Keep-alive para Supabase (pausa tras 7 días sin actividad)
    $keepAlive = @'
# .github/workflows/keep-alive.yml
# Ping anti-pausa para Supabase (7 días) y Neo4j AuraDB (3 días)
# Ejecuta cada 5 días a las 09:00 UTC

name: Keep-Alive Services

on:
  schedule:
    - cron: '0 9 */5 * *'   # Cada 5 días
  workflow_dispatch:         # Manual trigger

jobs:
  ping-services:
    runs-on: ubuntu-latest
    steps:
      - name: Ping Supabase (anti-pausa)
        run: |
          curl -s -o /dev/null -w "%{http_code}" \
            "${{ secrets.SUPABASE_URL }}/rest/v1/" \
            -H "apikey: ${{ secrets.SUPABASE_ANON_KEY }}"
          echo " → Supabase activo"

      - name: Ping API Oracle VM (anti-hibernación)
        run: |
          curl -s -o /dev/null -w "%{http_code}" \
            "${{ secrets.ORACLE_VM_URL }}/health" || true
          echo " → Oracle VM pingSent"

      - name: Ping Neo4j AuraDB (anti-pausa 3 días)
        run: |
          echo "Recordatorio: Neo4j AuraDB pausa tras 3 días sin uso"
          echo "Verificar: https://console.neo4j.io"

  deploy-frontend:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    needs: []
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - name: Install + Build Angular
        working-directory: frontend
        run: |
          npm ci
          npm run build -- --configuration production

      - name: Deploy a Vercel
        uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          working-directory: frontend/dist/juris-free-app

  deploy-workers:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }

      - name: Deploy Cloudflare Workers
        working-directory: workers/orchestrator
        run: |
          npm ci
          npx wrangler deploy
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
'@

    Set-Content -Path "$ProjectRoot/.github/workflows/keep-alive.yml" -Value $keepAlive

    # .env.example
    $envExample = @'
# .env.example — Copiar a .env y completar valores
# NUNCA subir .env al repositorio

# ── APIs LLM Gratuitas ────────────────────────
GEMINI_API_KEY=       # https://aistudio.google.com/app/apikey
GROQ_API_KEY=         # https://console.groq.com/keys
CEREBRAS_API_KEY=     # https://cloud.cerebras.ai/platform
OPENROUTER_API_KEY=   # https://openrouter.ai/keys
SAMBANOVA_API_KEY=    # https://cloud.sambanova.ai/apis (requiere registro email)

# ── Supabase ──────────────────────────────────
SUPABASE_URL=         # https://app.supabase.com → Project Settings → API
SUPABASE_ANON_KEY=    # Clave pública (safe para frontend)
SUPABASE_SERVICE_KEY= # Clave privada (SOLO backend, NUNCA en frontend)

# ── Oracle VM ─────────────────────────────────
ORACLE_VM_URL=        # https://TU_IP_PUBLICA (exponer via Cloudflare Tunnel)
ORACLE_SSH_KEY=       # Ruta al archivo .pem de Oracle

# ── Cloudflare ────────────────────────────────
CF_API_TOKEN=         # https://dash.cloudflare.com/profile/api-tokens
CF_ACCOUNT_ID=        # Dashboard Cloudflare → Account ID

# ── Vercel ────────────────────────────────────
VERCEL_TOKEN=         # https://vercel.com/account/tokens
VERCEL_ORG_ID=        # vercel projects ls
VERCEL_PROJECT_ID=    # vercel projects ls
'@

    Set-Content -Path "$ProjectRoot/.env.example" -Value $envExample
    New-Item -Path "$ProjectRoot/.github/workflows" -ItemType Directory -Force | Out-Null
    Write-OK "GitHub Actions + .env.example configurados"
}

# ─── 9. SCRIPTS POWERSHELL DE UTILIDAD ───────────────────────────────────────
function New-UtilityScripts {
    Write-Header "Generando scripts PowerShell de utilidad"

    # Script para obtener todas las API keys gratuitas
    $getApiKeys = @'
# scripts/get-api-keys.ps1
# Guía interactiva para obtener todas las API keys gratuitas

Write-Host "`n⚖️ JURIS-FREE Bolivia — Obtención de API Keys Gratuitas" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkCyan

$apis = @(
    @{
        Name    = "Google Gemini (RECOMENDADO - 1,500 req/día, 1M contexto)"
        URL     = "https://aistudio.google.com/app/apikey"
        EnvVar  = "GEMINI_API_KEY"
        Steps   = @("1. Ir a aistudio.google.com", "2. Iniciar sesión con Gmail", "3. 'Get API Key' → 'Create API Key'", "4. Copiar la clave (empieza con AIza...)")
        Free    = $true
        Card    = $false
    },
    @{
        Name    = "Groq (Más rápido - 315 TPS, Llama 3.3 70B)"
        URL     = "https://console.groq.com/keys"
        EnvVar  = "GROQ_API_KEY"
        Steps   = @("1. Ir a console.groq.com", "2. Registrarse con email", "3. 'API Keys' → 'Create API Key'", "4. Copiar la clave (empieza con gsk_...)")
        Free    = $true
        Card    = $false
    },
    @{
        Name    = "Cerebras (Mayor volumen - 1M tokens/día)"
        URL     = "https://cloud.cerebras.ai/platform"
        EnvVar  = "CEREBRAS_API_KEY"
        Steps   = @("1. Ir a cloud.cerebras.ai", "2. Registrarse con email", "3. API Keys → New API Key")
        Free    = $true
        Card    = $false
    },
    @{
        Name    = "OpenRouter (30+ modelos gratuitos)"
        URL     = "https://openrouter.ai/keys"
        EnvVar  = "OPENROUTER_API_KEY"
        Steps   = @("1. Ir a openrouter.ai", "2. Sign Up → API Keys", "3. Create Key (los modelos :free son $0)")
        Free    = $true
        Card    = $false
    },
    @{
        Name    = "SambaNova (DeepSeek V3 gratis)"
        URL     = "https://cloud.sambanova.ai/apis"
        EnvVar  = "SAMBANOVA_API_KEY"
        Steps   = @("1. Ir a cloud.sambanova.ai", "2. Registrarse (requiere email de trabajo/edu)", "3. APIs → Generate Key")
        Free    = $true
        Card    = $false
    }
)

foreach ($api in $apis) {
    Write-Host "`n📋 $($api.Name)" -ForegroundColor Yellow
    Write-Host "   URL: $($api.URL)" -ForegroundColor DarkCyan
    Write-Host "   Variable: $($api.EnvVar)" -ForegroundColor White

    foreach ($step in $api.Steps) {
        Write-Host "   $step" -ForegroundColor Gray
    }

    $open = Read-Host "   ¿Abrir en el navegador? (s/n)"
    if ($open -eq 's' -or $open -eq 'S') {
        Start-Process $api.URL
    }

    $key = Read-Host "   Pega tu API key (o Enter para saltar)"
    if ($key) {
        # Agregar al .env
        $envLine = "$($api.EnvVar)=$key"
        Add-Content -Path ".env" -Value $envLine
        Write-Host "   ✓ Guardado en .env" -ForegroundColor Green
    }
}

Write-Host "`n✅ Proceso completado. Revisa tu archivo .env" -ForegroundColor Green
Write-Host "   Siguiente paso: .\scripts\setup-supabase.ps1" -ForegroundColor Cyan
'@

    # Script de deploy completo
    $deployScript = @'
# scripts/deploy.ps1
# Deploy completo de JURIS-FREE Bolivia

param(
    [switch]$FrontendOnly,
    [switch]$WorkersOnly,
    [switch]$BackendOnly
)

function Write-Step { param($msg) Write-Host "  ▸ $msg" -ForegroundColor White }
function Write-OK   { param($msg) Write-Host "  ✓ $msg" -ForegroundColor Green }

Write-Host "`n🚀 Deploy JURIS-FREE Bolivia" -ForegroundColor Cyan

if (-not $WorkersOnly -and -not $BackendOnly) {
    Write-Host "`n[1/3] Frontend Angular → Vercel" -ForegroundColor Yellow
    Set-Location .\frontend
    Write-Step "Build de producción..."
    npm run build -- --configuration production
    Write-Step "Deploy a Vercel..."
    npx vercel --prod
    Set-Location ..
    Write-OK "Frontend desplegado"
}

if (-not $FrontendOnly -and -not $BackendOnly) {
    Write-Host "`n[2/3] Cloudflare Workers" -ForegroundColor Yellow
    Set-Location .\workers\orchestrator
    Write-Step "Deploy orquestador..."
    npx wrangler deploy
    Set-Location ..\..
    Write-OK "Workers desplegados"
}

if (-not $FrontendOnly -and -not $WorkersOnly) {
    Write-Host "`n[3/3] Backend FastAPI (Oracle VM via SSH)" -ForegroundColor Yellow
    $oracleIp = (Get-Content .env | Where-Object { $_ -match "^ORACLE_VM_URL" } | ForEach-Object { $_.Split('=')[1].Replace('https://','') })
    Write-Step "Copiando archivos al servidor..."
    scp -r .\backend\ ubuntu@${oracleIp}:~/juris-free/
    Write-Step "Reiniciando servicio en Oracle VM..."
    ssh ubuntu@$oracleIp "cd ~/juris-free && ./scripts/restart-backend.sh"
    Write-OK "Backend actualizado en Oracle VM"
}

Write-Host "`n✅ Deploy completo" -ForegroundColor Green
'@

    Set-Content -Path "$ProjectRoot/scripts/get-api-keys.ps1" -Value $getApiKeys
    Set-Content -Path "$ProjectRoot/scripts/deploy.ps1"       -Value $deployScript
    Write-OK "Scripts de utilidad generados"
}

# ─── 10. .gitignore y README ──────────────────────────────────────────────────
function New-ProjectFiles {
    Write-Header "Creando archivos del proyecto"

    $gitignore = @'
# Secrets — NUNCA subir al repo
.env
*.pem
*.key
*.p12

# Node
node_modules/
dist/
.angular/

# Python
__pycache__/
*.pyc
venv/
.venv/

# Embeddings (archivos grandes)
data/embeddings/*.faiss
data/embeddings/*.pkl
data/raw/*.pdf
data/processed/*.json

# Cloudflare
.wrangler/

# OS
.DS_Store
Thumbs.db
'@

    $readme = @'
# ⚖️ JURIS-FREE Bolivia

Sistema jurídico inteligente **100% gratuito** para abogados bolivianos.

## Stack Tecnológico
- **Frontend**: Angular 17 + TypeScript + PWA → Vercel
- **Backend**: FastAPI (Python) → Oracle Cloud Always Free (4 ARM cores, 24GB RAM)
- **Agentes**: Cloudflare Workers (TypeScript) — arquitectura L-MARS
- **Base de datos**: Supabase PostgreSQL + pgvector
- **LLMs**: Gemini 2.5 Flash + Groq + Cerebras + OpenRouter (fallover automático)

## Instalación rápida (PowerShell 7)

```powershell
# 1. Clonar y configurar
git clone https://github.com/TU_USUARIO/juris-free-bolivia
cd juris-free-bolivia

# 2. Obtener API keys gratuitas (guía interactiva)
.\scripts\get-api-keys.ps1

# 3. Instalar dependencias y generar proyecto Angular
.\setup-juris-free.ps1

# 4. Desarrollo local
.\scripts\dev.ps1
```

## Fuentes legales Bolivia
- 🏛️ Gaceta Oficial: https://www.gacetaoficialdebolivia.gob.bo
- ⚖️ Tribunal Constitucional Plurinacional: https://www.tribunalconstitucional.bo
- 🏛️ Órgano Judicial: https://www.organojudicial.gob.bo

## Costo mensual: $0.00
'@

    Set-Content -Path "$ProjectRoot/.gitignore" -Value $gitignore
    Set-Content -Path "$ProjectRoot/README.md"  -Value $readme
    New-Item -Path "$ProjectRoot/.github/workflows" -ItemType Directory -Force | Out-Null
    Write-OK ".gitignore y README.md creados"
}

# ─── FUNCIÓN PRINCIPAL ────────────────────────────────────────────────────────
function Main {
    Show-Banner

    $startTime = Get-Date

    try {
        if (-not $SkipDepsCheck) {
            Test-Dependencies
        }

        Install-GlobalTools
        New-ProjectStructure

        if (-not $WorkersOnly -and -not $BackendOnly) {
            New-AngularProject
            New-AngularModules
        }

        if (-not $FrontendOnly -and -not $BackendOnly) {
            New-CloudflareWorkers
        }

        if (-not $FrontendOnly -and -not $WorkersOnly) {
            New-FastAPIBackend
        }

        New-GitHubActions
        New-UtilityScripts
        New-ProjectFiles

        $elapsed = [int](New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds

        Write-Host "`n" -NoNewline
        Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║  ✅ JURIS-FREE Bolivia configurado en ${elapsed}s  ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Green

        Write-Host "`n📋 Próximos pasos:" -ForegroundColor Cyan
        Write-Host "  1. cd $ProjectRoot" -ForegroundColor White
        Write-Host "  2. .\scripts\get-api-keys.ps1    # Obtener API keys gratuitas" -ForegroundColor White
        Write-Host "  3. cd frontend && ng serve        # Dev server Angular" -ForegroundColor White
        Write-Host "  4. cd backend  && uvicorn api.main:app --reload  # Backend" -ForegroundColor White
        Write-Host "  5. .\scripts\deploy.ps1           # Deploy a producción" -ForegroundColor White

        Write-Host "`n🔗 Servicios a configurar manualmente:" -ForegroundColor Yellow
        Write-Host "  • Oracle Cloud Always Free: https://cloud.oracle.com/free" -ForegroundColor White
        Write-Host "  • Supabase Free:            https://supabase.com" -ForegroundColor White
        Write-Host "  • Cloudflare Workers:       https://dash.cloudflare.com" -ForegroundColor White
        Write-Host "  • Vercel:                   https://vercel.com" -ForegroundColor White
        Write-Host "  • Neo4j AuraDB Free:        https://console.neo4j.io" -ForegroundColor White

    } catch {
        Write-Fail "Error durante la configuración: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
        exit 1
    }
}

# Ejecutar
Main
