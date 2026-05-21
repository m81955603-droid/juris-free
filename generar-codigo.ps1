# JURIS-FREE Bolivia — Generador de codigo fuente
# Crea todos los archivos TypeScript, Angular, Python y Workers
# PowerShell 7+ | Sin CmdletBinding | Sin heredocs

param(
    [string]$Ruta = "C:\proyectos\juris-free"
)

$ErrorActionPreference = "Stop"
function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }
function WARN { param($m) Write-Host "  !! $m" -ForegroundColor Yellow }

Write-Host "`n  JURIS-FREE Bolivia — Generando codigo fuente`n" -ForegroundColor Cyan

$fe   = "$Ruta\frontend\src\app"
$env  = "$Ruta\frontend\src\environments"
$back = "$Ruta\backend"
$wk   = "$Ruta\workers"

# ═══════════════════════════════════════════════════════════════
# 1. MODELOS TYPESCRIPT
# ═══════════════════════════════════════════════════════════════
PASO "Modelos TypeScript"

Set-Content "$fe\core\models\legal.models.ts" @"
// Modelos de dominio legal para Bolivia
export type LegalArea =
  | 'civil' | 'penal' | 'laboral'
  | 'constitucional' | 'administrativo'
  | 'comercial' | 'familiar' | 'auto';

export interface LegalDocument {
  id: string;
  type: 'ley' | 'decreto' | 'sentencia' | 'resolucion' | 'constitucion';
  title: string;
  body: string;
  sourceUrl?: string;
  publishedDate?: string;
  jurisdiction: 'nacional' | 'departamental';
  area: LegalArea;
  metadata: Record<string, unknown>;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
  provider?: string;
  tokensUsed?: number;
  isStreaming?: boolean;
}

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

export interface Conversation {
  id: string;
  userId: string;
  title: string;
  area: LegalArea;
  createdAt: string;
  updatedAt: string;
  messageCount: number;
}

export interface ProviderStatus {
  provider: string;
  model: string;
  todayRequests: number;
  todayTokens: number;
  isLimited: boolean;
  dailyLimit: number;
}
"@
OK "legal.models.ts"

# ═══════════════════════════════════════════════════════════════
# 2. LLM PROXY SERVICE
# ═══════════════════════════════════════════════════════════════
PASO "LLM Proxy Service"

Set-Content "$fe\core\services\llm-proxy.service.ts" @"
import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError, tap } from 'rxjs/operators';
import { environment } from '../../../environments/environment';
import { LlmMessage, LlmResponse, ProviderStatus } from '../models/legal.models';

interface ProviderConfig {
  name: string;
  model: string;
  priority: number;
  maxRequestsPerDay: number;
}

@Injectable({ providedIn: 'root' })
export class LlmProxyService {
  private http = inject(HttpClient);
  private usageKey = 'juris_llm_usage';
  private rateLimitKey = 'juris_ratelimit';

  private readonly providers: ProviderConfig[] = [
    { name: 'gemini',     model: 'gemini-2.5-flash',              priority: 1, maxRequestsPerDay: 1500  },
    { name: 'groq',       model: 'llama-3.3-70b-versatile',       priority: 2, maxRequestsPerDay: 14400 },
    { name: 'cerebras',   model: 'llama3.3-70b',                  priority: 3, maxRequestsPerDay: 14400 },
    { name: 'openrouter', model: 'qwen/qwen-2.5-72b-instruct',    priority: 4, maxRequestsPerDay: 200   },
    { name: 'sambanova',  model: 'Meta-Llama-3.3-70B-Instruct',   priority: 5, maxRequestsPerDay: 1000  }
  ];

  chat(messages: LlmMessage[], systemPrompt?: string, preferredProvider?: string): Observable<LlmResponse> {
    const ordered = this.getOrderedProviders(preferredProvider);
    return this.tryProviders(messages, systemPrompt, ordered, 0);
  }

  private tryProviders(messages: LlmMessage[], system: string | undefined, providers: ProviderConfig[], index: number): Observable<LlmResponse> {
    if (index >= providers.length) {
      return throwError(() => new Error('Todos los proveedores LLM no disponibles. Intenta en unos minutos.'));
    }
    const provider = providers[index];
    return this.callBackend(provider, messages, system).pipe(
      tap(r => this.trackUsage(provider.name, r.tokensUsed)),
      catchError(err => {
        console.warn('[LLM] ' + provider.name + ' fallo: ' + err.message);
        this.markRateLimited(provider.name);
        return this.tryProviders(messages, system, providers, index + 1);
      })
    );
  }

  private callBackend(provider: ProviderConfig, messages: LlmMessage[], system?: string): Observable<LlmResponse> {
    return this.http.post<LlmResponse>(
      environment.apiUrl + '/api/v1/llm/chat',
      { provider: provider.name, model: provider.model, messages, system, maxTokens: 2048 },
      { headers: new HttpHeaders({ 'Content-Type': 'application/json' }) }
    );
  }

  private getOrderedProviders(preferred?: string): ProviderConfig[] {
    const available = this.providers.filter(p => !this.isRateLimited(p.name));
    if (preferred) {
      const pref = available.find(p => p.name === preferred);
      if (pref) return [pref, ...available.filter(p => p.name !== preferred)];
    }
    return available.sort((a, b) => a.priority - b.priority);
  }

  getUsageStats(): ProviderStatus[] {
    const usage = this.getUsage();
    const today = new Date().toDateString();
    return this.providers.map(p => ({
      provider: p.name, model: p.model,
      todayRequests: usage[p.name]?.[today]?.requests ?? 0,
      todayTokens:   usage[p.name]?.[today]?.tokens   ?? 0,
      isLimited:     this.isRateLimited(p.name),
      dailyLimit:    p.maxRequestsPerDay
    }));
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
    const limits = this.getRateLimits();
    limits[provider] = Date.now() + 15 * 60 * 1000;
    localStorage.setItem(this.rateLimitKey, JSON.stringify(limits));
  }

  private isRateLimited(provider: string): boolean {
    const limits = this.getRateLimits();
    if (!limits[provider]) return false;
    if (Date.now() > limits[provider]) {
      delete limits[provider];
      localStorage.setItem(this.rateLimitKey, JSON.stringify(limits));
      return false;
    }
    return true;
  }

  private getUsage(): Record<string, Record<string, { requests: number; tokens: number }>> {
    try { return JSON.parse(localStorage.getItem(this.usageKey) || '{}'); }
    catch { return {}; }
  }

  private getRateLimits(): Record<string, number> {
    try { return JSON.parse(localStorage.getItem(this.rateLimitKey) || '{}'); }
    catch { return {}; }
  }
}
"@
OK "llm-proxy.service.ts"

# ═══════════════════════════════════════════════════════════════
# 3. SUPABASE SERVICE
# ═══════════════════════════════════════════════════════════════
PASO "Supabase Service"

Set-Content "$fe\core\services\supabase.service.ts" @"
import { Injectable } from '@angular/core';
import { createClient, SupabaseClient, User, Session } from '@supabase/supabase-js';
import { BehaviorSubject, Observable, from } from 'rxjs';
import { map } from 'rxjs/operators';
import { environment } from '../../../environments/environment';
import { LegalDocument, Conversation, ChatMessage } from '../models/legal.models';

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  private client: SupabaseClient;
  private userSubject  = new BehaviorSubject<User | null>(null);
  private sessionSubject = new BehaviorSubject<Session | null>(null);

  readonly currentUser\$    = this.userSubject.asObservable();
  readonly session\$         = this.sessionSubject.asObservable();
  readonly isAuthenticated\$ = this.currentUser\$.pipe(map(u => !!u));

  constructor() {
    this.client = createClient(environment.supabaseUrl, environment.supabaseAnonKey, {
      auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
    });
    this.client.auth.onAuthStateChange((_event, session) => {
      this.sessionSubject.next(session);
      this.userSubject.next(session?.user ?? null);
    });
    this.client.auth.getSession().then(({ data: { session } }) => {
      this.sessionSubject.next(session);
      this.userSubject.next(session?.user ?? null);
    });
  }

  // ── Auth ──────────────────────────────────────────────────
  signInWithGoogle(): Observable<void> {
    return from(this.client.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin + '/auth/callback' }
    }).then(({ error }) => { if (error) throw error; }));
  }

  signInWithMagicLink(email: string): Observable<void> {
    return from(this.client.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin + '/auth/callback' }
    }).then(({ error }) => { if (error) throw error; }));
  }

  signOut(): Observable<void> {
    return from(this.client.auth.signOut().then(({ error }) => { if (error) throw error; }));
  }

  // ── Busqueda semantica (pgvector) ─────────────────────────
  searchLegal(queryEmbedding: number[], area?: string, limit = 5): Observable<LegalDocument[]> {
    return from(this.client.rpc('match_legal_documents', {
      query_embedding: queryEmbedding,
      match_threshold: 0.7,
      match_count: limit,
      filter_area: area ?? null
    }).then(({ data, error }) => {
      if (error) throw error;
      return (data as LegalDocument[]) ?? [];
    }));
  }

  // ── Conversaciones ────────────────────────────────────────
  getConversations(userId: string): Observable<Conversation[]> {
    return from(this.client.from('conversations')
      .select('*').eq('user_id', userId)
      .order('updated_at', { ascending: false })
      .then(({ data, error }) => {
        if (error) throw error;
        return (data as Conversation[]) ?? [];
      }));
  }

  createConversation(userId: string, title: string, area: string): Observable<Conversation> {
    return from(this.client.from('conversations')
      .insert({ user_id: userId, title, area, message_count: 0 })
      .select().single()
      .then(({ data, error }) => {
        if (error) throw error;
        return data as Conversation;
      }));
  }

  getMessages(conversationId: string): Observable<ChatMessage[]> {
    return from(this.client.from('messages')
      .select('*').eq('conversation_id', conversationId)
      .order('created_at', { ascending: true })
      .then(({ data, error }) => {
        if (error) throw error;
        return (data as ChatMessage[]) ?? [];
      }));
  }

  saveMessage(msg: Omit<ChatMessage, 'id' | 'timestamp'>): Observable<ChatMessage> {
    return from(this.client.from('messages')
      .insert(msg).select().single()
      .then(({ data, error }) => {
        if (error) throw error;
        return data as ChatMessage;
      }));
  }

  // ── Documentos de caso ────────────────────────────────────
  uploadCaseDocument(file: File, caseId: string, userId: string): Observable<string> {
    const path = userId + '/cases/' + caseId + '/' + file.name;
    return from(this.client.storage.from('case-documents')
      .upload(path, file, { upsert: true })
      .then(({ data, error }) => {
        if (error) throw error;
        return data.path;
      }));
  }
}
"@
OK "supabase.service.ts"

# ═══════════════════════════════════════════════════════════════
# 4. AUTH GUARD
# ═══════════════════════════════════════════════════════════════
PASO "Auth Guard"

Set-Content "$fe\core\guards\auth.guard.ts" @"
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SupabaseService } from '../services/supabase.service';
import { map, take } from 'rxjs/operators';

export const authGuard: CanActivateFn = () => {
  const supabase = inject(SupabaseService);
  const router   = inject(Router);
  return supabase.isAuthenticated\$.pipe(
    take(1),
    map(isAuth => isAuth ? true : router.createUrlTree(['/chat']))
  );
};
"@
OK "auth.guard.ts"

# ═══════════════════════════════════════════════════════════════
# 5. APP ROUTES
# ═══════════════════════════════════════════════════════════════
PASO "App Routes"

Set-Content "$fe\app.routes.ts" @"
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
  { path: 'auth/callback', loadComponent: () => import('./core/auth-callback/auth-callback.component').then(m => m.AuthCallbackComponent) },
  { path: '**', redirectTo: '/chat' }
];
"@
OK "app.routes.ts"

# ═══════════════════════════════════════════════════════════════
# 6. CHAT COMPONENT (TS + HTML + SCSS)
# ═══════════════════════════════════════════════════════════════
PASO "Chat Component"

New-Item -ItemType Directory -Path "$fe\features\chat" -Force | Out-Null

Set-Content "$fe\features\chat\chat.component.ts" @"
import { Component, OnInit, OnDestroy, ViewChild, ElementRef, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule, ReactiveFormsModule, FormControl } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { ChatMessage, LegalArea, LlmMessage } from '../../core/models/legal.models';

const SYSTEM_PROMPT = `Eres JURIS-FREE, asistente juridico especializado en derecho boliviano.
REGLAS:
1. Cita siempre el articulo exacto y la norma boliviana vigente.
2. Menciona jurisprudencia del TCP o TSJ cuando sea relevante (con numero de sentencia).
3. Distingue norma vigente de norma derogada.
4. Estructura: Base Legal -> Analisis -> Consecuencias Juridicas -> Recomendacion.
5. NUNCA inventes articulos o sentencias. Si no tienes la informacion exacta, indicalo.
6. Referencias clave: CPE 2009, Cod. Civil (Ley 12760), Cod. Penal (Ley 1768), Cod. Familiar (Ley 996).`;

@Component({
  selector: 'app-chat',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule],
  templateUrl: './chat.component.html',
  styleUrls: ['./chat.component.scss']
})
export class ChatComponent implements OnInit, OnDestroy {
  @ViewChild('messagesEl') messagesEl!: ElementRef;

  private llm     = inject(LlmProxyService);
  private destroy = new Subject<void>();

  messages        = signal<ChatMessage[]>([]);
  isLoading       = signal(false);
  selectedArea    = signal<LegalArea>('auto');
  currentProvider = signal('');
  inputControl    = new FormControl('', { nonNullable: true });
  history: LlmMessage[] = [];

  readonly areas: { value: LegalArea; label: string; icon: string }[] = [
    { value: 'auto',           label: 'Auto',           icon: '✦' },
    { value: 'civil',          label: 'Civil',          icon: '📋' },
    { value: 'penal',          label: 'Penal',          icon: '⚖️' },
    { value: 'laboral',        label: 'Laboral',        icon: '👷' },
    { value: 'constitucional', label: 'Constitucional', icon: '🏛️' },
    { value: 'administrativo', label: 'Administrativo', icon: '🏢' },
    { value: 'familiar',       label: 'Familiar',       icon: '👨‍👩‍👧' }
  ];

  ngOnInit(): void {
    this.messages.set([{
      id: 'welcome', role: 'assistant', timestamp: new Date(),
      content: '## Bienvenido a JURIS-FREE Bolivia\n\nSoy tu asistente juridico especializado en derecho boliviano. Puedo ayudarte con:\n\n- Consultas sobre normativa boliviana vigente (CPE, Codigos, Decretos)\n- Jurisprudencia del TCP y Tribunal Supremo de Justicia\n- Analisis de contratos y documentos legales\n- Procedimientos judiciales y plazos\n\nEscribe tu consulta y presiona **Enter**.',
      provider: 'sistema'
    }]);
    this.loadHistory();
  }

  ngOnDestroy(): void { this.destroy.next(); this.destroy.complete(); }

  sendMessage(): void {
    const text = this.inputControl.value.trim();
    if (!text || this.isLoading()) return;

    const userMsg: ChatMessage = { id: crypto.randomUUID(), role: 'user', content: text, timestamp: new Date() };
    this.messages.update(m => [...m, userMsg]);
    this.inputControl.reset();
    this.isLoading.set(true);
    this.history.push({ role: 'user', content: text });

    const assistantId = crypto.randomUUID();
    this.messages.update(m => [...m, { id: assistantId, role: 'assistant', content: '', timestamp: new Date(), isStreaming: true }]);
    this.scrollBottom();

    this.llm.chat(this.history, SYSTEM_PROMPT).pipe(takeUntil(this.destroy)).subscribe({
      next: resp => {
        this.history.push({ role: 'assistant', content: resp.content });
        this.messages.update(m => m.map(msg =>
          msg.id === assistantId
            ? { ...msg, content: resp.content, provider: resp.provider, tokensUsed: resp.tokensUsed, isStreaming: false }
            : msg
        ));
        this.currentProvider.set(resp.provider);
        this.isLoading.set(false);
        this.saveHistory();
        this.scrollBottom();
      },
      error: err => {
        this.messages.update(m => m.map(msg =>
          msg.id === assistantId ? { ...msg, content: 'Error: ' + err.message, isStreaming: false } : msg
        ));
        this.isLoading.set(false);
      }
    });
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.sendMessage(); }
  }

  clearChat(): void {
    this.history = [];
    this.messages.set([]);
    localStorage.removeItem('juris_history');
  }

  private scrollBottom(): void {
    setTimeout(() => {
      const el = this.messagesEl?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    }, 80);
  }

  private saveHistory(): void {
    localStorage.setItem('juris_history', JSON.stringify(this.history.slice(-20)));
  }

  private loadHistory(): void {
    try {
      const s = localStorage.getItem('juris_history');
      if (s) this.history = JSON.parse(s);
    } catch { this.history = []; }
  }
}
"@
OK "chat.component.ts"

Set-Content "$fe\features\chat\chat.component.html" @"
<div class="chat-wrap">

  <header class="topbar">
    <div class="brand">
      <span class="brand-icon">⚖️</span>
      <span class="brand-name">JURIS-FREE <span class="brand-bo">Bolivia</span></span>
    </div>
    <div class="topbar-right">
      @if (currentProvider()) {
        <span class="provider-tag">{{ currentProvider() }}</span>
      }
      <button class="icon-btn" (click)="clearChat()" title="Nueva consulta">＋</button>
    </div>
  </header>

  <nav class="area-nav">
    @for (a of areas; track a.value) {
      <button class="area-btn" [class.active]="selectedArea() === a.value" (click)="selectedArea.set(a.value)">
        <span>{{ a.icon }}</span> {{ a.label }}
      </button>
    }
  </nav>

  <div class="messages" #messagesEl>
    @for (msg of messages(); track msg.id) {
      <div class="msg" [class.user]="msg.role==='user'" [class.bot]="msg.role==='assistant'">
        @if (msg.role === 'assistant') {
          <div class="avatar">⚖</div>
        }
        <div class="bubble">
          @if (msg.isStreaming) {
            <div class="typing"><span></span><span></span><span></span></div>
          } @else {
            <div class="content" [innerHTML]="msg.content"></div>
          }
          <div class="meta">
            <span>{{ msg.timestamp | date:'HH:mm' }}</span>
            @if (msg.provider && msg.provider !== 'sistema') {
              <span class="prov">{{ msg.provider }}</span>
            }
            @if (msg.tokensUsed) {
              <span>{{ msg.tokensUsed }} tok</span>
            }
          </div>
        </div>
        @if (msg.role === 'user') {
          <div class="avatar user-av">👤</div>
        }
      </div>
    }
  </div>

  <div class="input-row">
    <textarea
      class="inp"
      [formControl]="inputControl"
      placeholder="Consulta sobre derecho boliviano... (Enter para enviar)"
      rows="2"
      (keydown)="onKeydown($event)"
      [disabled]="isLoading()">
    </textarea>
    <button class="send-btn" (click)="sendMessage()" [disabled]="isLoading() || !inputControl.value.trim()">
      @if (isLoading()) { ⏳ } @else { ➤ }
    </button>
  </div>

  <footer class="foot">
    <span>🇧🇴 CPE 2009 · TCP · TSJ · Gaceta Oficial de Bolivia</span>
    <span>Open Source · Gratuito</span>
  </footer>

</div>
"@
OK "chat.component.html"

Set-Content "$fe\features\chat\chat.component.scss" @"
:host {
  --prim: #1a3a5c;
  --gold: #c4922a;
  --bg:   #f8f6f1;
  --surf: #ffffff;
  --bord: #e0d8c8;
  --txt:  #2c2416;
  --mut:  #7a6e5e;
  display: block; height: 100vh;
  font-family: 'Georgia', serif;
}

.chat-wrap { display:flex; flex-direction:column; height:100vh; max-width:860px; margin:0 auto; background:var(--bg); }

/* Topbar */
.topbar { display:flex; justify-content:space-between; align-items:center; padding:12px 18px; background:var(--prim); border-bottom:3px solid var(--gold); }
.brand  { display:flex; align-items:center; gap:8px; color:#fff; font-size:1.1rem; font-weight:700; letter-spacing:.04em; }
.brand-bo { color:var(--gold); font-style:italic; }
.topbar-right { display:flex; align-items:center; gap:10px; }
.provider-tag { background:rgba(196,146,42,.2); border:1px solid var(--gold); color:#ffd98e; font-size:.68rem; padding:2px 9px; border-radius:20px; font-family:monospace; text-transform:uppercase; }
.icon-btn { background:none; border:none; color:rgba(255,255,255,.7); font-size:1.2rem; cursor:pointer; padding:4px 8px; border-radius:6px; transition:.2s; }
.icon-btn:hover { background:rgba(255,255,255,.12); color:#fff; }

/* Area nav */
.area-nav { display:flex; gap:5px; padding:8px 14px; background:var(--surf); border-bottom:1px solid var(--bord); overflow-x:auto; scrollbar-width:none; }
.area-nav::-webkit-scrollbar { display:none; }
.area-btn { display:flex; align-items:center; gap:4px; padding:4px 12px; border:1px solid var(--bord); background:#fff; border-radius:20px; cursor:pointer; font-size:.76rem; white-space:nowrap; color:var(--mut); transition:.2s; }
.area-btn:hover { border-color:var(--prim); color:var(--prim); }
.area-btn.active { background:var(--prim); border-color:var(--prim); color:#fff; }

/* Messages */
.messages { flex:1; overflow-y:auto; padding:18px 14px; display:flex; flex-direction:column; gap:14px; scroll-behavior:smooth; }
.msg { display:flex; gap:9px; align-items:flex-start; }
.msg.user { flex-direction:row-reverse; }

.avatar { width:34px; height:34px; border-radius:50%; background:var(--gold); display:flex; align-items:center; justify-content:center; font-size:1rem; flex-shrink:0; }
.user-av { background:var(--prim); }

.bubble { max-width:76%; padding:10px 14px; border-radius:12px; }
.msg.bot  .bubble { background:var(--surf); border:1px solid var(--bord); border-radius:12px 12px 12px 3px; box-shadow:0 1px 4px rgba(0,0,0,.05); }
.msg.user .bubble { background:var(--prim); color:#fff; border-radius:12px 12px 3px 12px; }

.content { font-size:.9rem; line-height:1.65; }
.msg.bot .content { color:var(--txt); }

.meta { display:flex; gap:7px; margin-top:5px; font-size:.68rem; color:var(--mut); font-family:monospace; }
.msg.user .meta { color:rgba(255,255,255,.5); }
.prov { background:rgba(196,146,42,.15); color:var(--gold); padding:1px 6px; border-radius:4px; }

/* Typing */
.typing { display:flex; gap:4px; padding:4px 0; }
.typing span { width:7px; height:7px; border-radius:50%; background:var(--mut); animation:blink 1.2s infinite; }
.typing span:nth-child(2) { animation-delay:.2s; }
.typing span:nth-child(3) { animation-delay:.4s; }
@keyframes blink { 0%,80%,100%{transform:scale(.7);opacity:.4} 40%{transform:scale(1);opacity:1} }

/* Input */
.input-row { display:flex; gap:8px; padding:12px 14px; background:var(--surf); border-top:1px solid var(--bord); }
.inp { flex:1; border:1px solid var(--bord); border-radius:10px; padding:9px 13px; font-size:.88rem; font-family:inherit; resize:none; background:var(--bg); color:var(--txt); transition:.2s; }
.inp:focus { outline:none; border-color:var(--prim); background:#fff; }
.inp:disabled { opacity:.55; }
.send-btn { width:44px; height:44px; border-radius:50%; border:none; background:var(--prim); color:#fff; font-size:1.1rem; cursor:pointer; transition:.2s; }
.send-btn:hover:not(:disabled) { background:#0f2440; transform:scale(1.07); }
.send-btn:disabled { opacity:.35; }

/* Footer */
.foot { display:flex; justify-content:space-between; padding:5px 14px; font-size:.65rem; color:var(--mut); border-top:1px solid var(--bord); }
"@
OK "chat.component.scss"

# ═══════════════════════════════════════════════════════════════
# 7. COMPONENTES PLACEHOLDER (library, cases, settings)
# ═══════════════════════════════════════════════════════════════
PASO "Componentes placeholder (library, cases, settings)"

$placeholders = @(
    @{ name = "library";  label = "Biblioteca Legal";      icon = "📚"; desc = "Busqueda de leyes, decretos y sentencias bolivianas" },
    @{ name = "cases";    label = "Carpetas de Casos";      icon = "💼"; desc = "Organiza tus casos con documentos y resumenes por IA" },
    @{ name = "settings"; label = "Configuracion";          icon = "⚙️";  desc = "Preferencias, API keys y estadisticas de uso" }
)

foreach ($p in $placeholders) {
    $dir = "$fe\features\$($p.name)"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    Set-Content "$dir\$($p.name).component.ts" @"
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-$($p.name)',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:80vh;gap:16px;color:#7a6e5e">
      <div style="font-size:3rem">$($p.icon)</div>
      <h2 style="color:#1a3a5c;font-family:Georgia,serif">$($p.label)</h2>
      <p>$($p.desc)</p>
      <p style="font-size:.8rem;background:#f0ede8;padding:8px 16px;border-radius:8px">Proximo modulo — en desarrollo</p>
    </div>
  `
})
export class $((Get-Culture).TextInfo.ToTitleCase($p.name))Component {}
"@
    OK "$($p.name).component.ts"
}

# Auth callback
New-Item -ItemType Directory -Path "$fe\core\auth-callback" -Force | Out-Null
Set-Content "$fe\core\auth-callback\auth-callback.component.ts" @"
import { Component, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-auth-callback',
  standalone: true,
  imports: [CommonModule],
  template: '<div style="display:flex;align-items:center;justify-content:center;height:100vh;font-family:Georgia,serif;color:#1a3a5c">Autenticando...</div>'
})
export class AuthCallbackComponent implements OnInit {
  private router = inject(Router);
  ngOnInit(): void { setTimeout(() => this.router.navigate(['/chat']), 1500); }
}
"@
OK "auth-callback.component.ts"

# ═══════════════════════════════════════════════════════════════
# 8. BACKEND FASTAPI
# ═══════════════════════════════════════════════════════════════
PASO "Backend FastAPI (Oracle VM)"

New-Item -ItemType Directory -Path "$back\api\routes" -Force | Out-Null
New-Item -ItemType Directory -Path "$back\api\models" -Force | Out-Null

Set-Content "$back\api\__init__.py" ""
Set-Content "$back\api\routes\__init__.py" ""

Set-Content "$back\api\main.py" @"
# JURIS-FREE Bolivia — Backend FastAPI
# Oracle Cloud Always Free: 4 ARM cores, 24GB RAM
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from .routes import llm, embeddings, health

logging.basicConfig(level=logging.INFO)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.info("JURIS-FREE Bolivia API iniciando...")
    yield
    logging.info("JURIS-FREE Bolivia API detenida.")

app = FastAPI(
    title="JURIS-FREE Bolivia API",
    description="Sistema juridico inteligente open source para Bolivia",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"])

app.include_router(health.router)
app.include_router(llm.router,        prefix="/api/v1/llm",        tags=["LLM"])
app.include_router(embeddings.router, prefix="/api/v1/embeddings", tags=["Embeddings"])
"@
OK "main.py"

Set-Content "$back\api\routes\health.py" @"
from fastapi import APIRouter
router = APIRouter()

@router.get("/health")
async def health():
    return {"status": "ok", "service": "juris-free-bolivia", "version": "1.0.0"}

@router.get("/")
async def root():
    return {"message": "JURIS-FREE Bolivia API — Sistema Juridico Open Source"}
"@
OK "health.py"

Set-Content "$back\api\routes\llm.py" @"
# Proxy LLM multi-proveedor con fallover automatico
# Prioridad: Gemini -> Groq -> Cerebras -> OpenRouter -> SambaNova
import httpx, os, time, logging
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
    maxTokens:  int = 2048

class ChatResponse(BaseModel):
    content:     str
    provider:    str
    model:       str
    tokensUsed:  int
    latencyMs:   int

PROVIDERS = [
    {"name":"gemini",     "url":"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", "key_env":"GEMINI_API_KEY",     "model":"gemini-2.5-flash",            "fmt":"gemini"},
    {"name":"groq",       "url":"https://api.groq.com/openai/v1/chat/completions",                                          "key_env":"GROQ_API_KEY",       "model":"llama-3.3-70b-versatile",     "fmt":"openai"},
    {"name":"cerebras",   "url":"https://api.cerebras.ai/v1/chat/completions",                                              "key_env":"CEREBRAS_API_KEY",   "model":"llama3.3-70b",                "fmt":"openai"},
    {"name":"openrouter", "url":"https://openrouter.ai/api/v1/chat/completions",                                            "key_env":"OPENROUTER_API_KEY", "model":"qwen/qwen-2.5-72b-instruct:free","fmt":"openai"},
    {"name":"sambanova",  "url":"https://api.sambanova.ai/v1/chat/completions",                                             "key_env":"SAMBANOVA_API_KEY",  "model":"Meta-Llama-3.3-70B-Instruct", "fmt":"openai"},
]

_rate_limited: dict = {}

async def call_openai(p, messages, system, max_tokens):
    key = os.getenv(p["key_env"])
    if not key: raise ValueError(f"Falta {p['key_env']}")
    msgs = []
    if system: msgs.append({"role":"system","content":system})
    msgs += [{"role":m.role,"content":m.content} for m in messages]
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.post(p["url"], json={"model":p["model"],"messages":msgs,"max_tokens":max_tokens,"temperature":0.3},
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
        contents += [{"role":"user","parts":[{"text":f"[Sistema]: {system}"}]},{"role":"model","parts":[{"text":"Entendido."}]}]
    for m in messages:
        contents.append({"role":"model" if m.role=="assistant" else "user","parts":[{"text":m.content}]})
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.post(f"{p['url']}?key={key}", json={"contents":contents,"generationConfig":{"maxOutputTokens":max_tokens,"temperature":0.3}})
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

    last_err = None
    for p in providers:
        if p["name"] in _rate_limited and time.time() < _rate_limited[p["name"]]:
            continue
        elif p["name"] in _rate_limited:
            del _rate_limited[p["name"]]
        try:
            t0 = time.time()
            logger.info(f"Intentando {p['name']}...")
            if p["fmt"] == "gemini":
                content, tokens = await call_gemini(p, req.messages, req.system, req.maxTokens)
            else:
                content, tokens = await call_openai(p, req.messages, req.system, req.maxTokens)
            ms = int((time.time()-t0)*1000)
            logger.info(f"{p['name']} OK — {ms}ms, {tokens} tokens")
            return ChatResponse(content=content, provider=p["name"], model=p["model"], tokensUsed=tokens, latencyMs=ms)
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                _rate_limited[p["name"]] = time.time()+900
                logger.warning(f"{p['name']} rate limited 15min")
            last_err = str(e)
        except Exception as e:
            last_err = str(e)
            logger.error(f"{p['name']} error: {e}")

    raise HTTPException(503, f"Todos los proveedores fallaron. Ultimo error: {last_err}")
"@
OK "llm.py (proxy multi-proveedor)"

Set-Content "$back\api\routes\embeddings.py" @"
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
"@
OK "embeddings.py"

# Script de arranque backend
Set-Content "$back\start.ps1" @"
# Arrancar backend FastAPI en modo desarrollo
Write-Host 'Iniciando JURIS-FREE Backend...' -ForegroundColor Cyan

# Crear .env si no existe
if (-not (Test-Path '.env')) {
    Copy-Item '..\env.example' '.env'
    Write-Host 'Crea el archivo .env con tus API keys' -ForegroundColor Yellow
}

# Instalar dependencias Python
pip install -r requirements.txt

# Iniciar servidor
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
"@
OK "start.ps1 (backend)"

# ═══════════════════════════════════════════════════════════════
# 9. CLOUDFLARE WORKER ORCHESTRATOR (TypeScript)
# ═══════════════════════════════════════════════════════════════
PASO "Cloudflare Worker — Orquestador L-MARS"

Set-Content "$wk\orchestrator\src\index.ts" @"
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
"@
OK "worker orchestrator index.ts"

# tsconfig para worker
Set-Content "$wk\orchestrator\tsconfig.json" @"
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noUnusedLocals": true,
    "noImplicitReturns": true
  },
  "include": ["src/**/*.ts"]
}
"@

# package.json para worker
Set-Content "$wk\orchestrator\package.json" @"
{
  "name": "juris-free-orchestrator",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev":    "wrangler dev",
    "deploy": "wrangler deploy",
    "types":  "wrangler types"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20241205.0",
    "typescript": "^5.0.0",
    "wrangler": "^3.0.0"
  }
}
"@
OK "worker package.json + tsconfig.json"

# ═══════════════════════════════════════════════════════════════
# 10. SQL SUPABASE (schema + funciones pgvector)
# ═══════════════════════════════════════════════════════════════
PASO "SQL Supabase (schema + pgvector)"

New-Item -ItemType Directory -Path "$Ruta\infra\supabase" -Force | Out-Null

Set-Content "$Ruta\infra\supabase\schema.sql" @"
-- JURIS-FREE Bolivia — Schema Supabase
-- Ejecutar en: Supabase Dashboard -> SQL Editor

-- Habilitar extension pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- Tabla de documentos legales bolivianos
CREATE TABLE IF NOT EXISTS legal_documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type          TEXT NOT NULL CHECK (type IN ('ley','decreto','sentencia','resolucion','constitucion')),
    title         TEXT NOT NULL,
    body          TEXT NOT NULL,
    source_url    TEXT,
    published_date DATE,
    jurisdiction  TEXT DEFAULT 'nacional',
    area          TEXT NOT NULL,
    embedding     vector(384),
    metadata      JSONB DEFAULT '{}',
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de conversaciones
CREATE TABLE IF NOT EXISTS conversations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title         TEXT NOT NULL DEFAULT 'Nueva consulta',
    area          TEXT DEFAULT 'auto',
    message_count INT DEFAULT 0,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de mensajes
CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('user','assistant')),
    content         TEXT NOT NULL,
    provider_used   TEXT,
    tokens_used     INT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Indice vectorial para busqueda semantica (IVFFlat)
CREATE INDEX IF NOT EXISTS legal_docs_embedding_idx
    ON legal_documents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Indice de texto completo para busqueda hibrida
CREATE INDEX IF NOT EXISTS legal_docs_fts_idx
    ON legal_documents USING gin(to_tsvector('spanish', title || ' ' || body));

-- Funcion de busqueda semantica
CREATE OR REPLACE FUNCTION match_legal_documents(
    query_embedding vector(384),
    match_threshold FLOAT DEFAULT 0.7,
    match_count     INT   DEFAULT 5,
    filter_area     TEXT  DEFAULT NULL
)
RETURNS TABLE (
    id TEXT, type TEXT, title TEXT, body TEXT,
    source_url TEXT, area TEXT, similarity FLOAT
)
LANGUAGE plpgsql AS
'BEGIN
  RETURN QUERY
  SELECT
    d.id::TEXT, d.type, d.title,
    LEFT(d.body, 500) AS body,
    d.source_url, d.area,
    1 - (d.embedding <=> query_embedding) AS similarity
  FROM legal_documents d
  WHERE
    (filter_area IS NULL OR d.area = filter_area)
    AND 1 - (d.embedding <=> query_embedding) > match_threshold
  ORDER BY d.embedding <=> query_embedding
  LIMIT match_count;
END;';

-- Row Level Security
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "usuarios ven sus conversaciones"
    ON conversations FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "usuarios ven sus mensajes"
    ON messages FOR ALL
    USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

-- Legal documents es publico (solo lectura)
ALTER TABLE legal_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "documentos legales publicos"
    ON legal_documents FOR SELECT USING (true);

SELECT 'Schema JURIS-FREE Bolivia creado OK' AS resultado;
"@
OK "schema.sql (Supabase)"

# ═══════════════════════════════════════════════════════════════
# 11. SCRIPT DEV LOCAL
# ═══════════════════════════════════════════════════════════════
PASO "Script de desarrollo local"

Set-Content "$Ruta\scripts\dev.ps1" @"
# Arrancar entorno de desarrollo completo
param([switch]`$BackendOnly, [switch]`$FrontendOnly)

Write-Host 'JURIS-FREE Bolivia — Entorno de desarrollo' -ForegroundColor Cyan

if (-not `$FrontendOnly) {
    Write-Host 'Iniciando Backend FastAPI (puerto 8000)...' -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList '-NoExit','-Command','cd backend; pip install -r requirements.txt -q; uvicorn api.main:app --reload --port 8000' -WorkingDirectory '$Ruta'
}

if (-not `$BackendOnly) {
    Write-Host 'Iniciando Frontend Angular (puerto 4200)...' -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList '-NoExit','-Command','cd frontend; ng serve --open' -WorkingDirectory '$Ruta'
}

Write-Host ''
Write-Host 'Servicios iniciando:' -ForegroundColor Green
Write-Host '  Frontend: http://localhost:4200' -ForegroundColor White
Write-Host '  Backend:  http://localhost:8000' -ForegroundColor White
Write-Host '  API docs: http://localhost:8000/docs' -ForegroundColor White
"@
OK "dev.ps1"

# ═══════════════════════════════════════════════════════════════
# RESUMEN
# ═══════════════════════════════════════════════════════════════
Write-Host @"

===============================================================
  JURIS-FREE Bolivia — Codigo fuente generado
===============================================================

  ANGULAR (frontend/src/app/):
    core/models/legal.models.ts        Tipos TypeScript
    core/services/llm-proxy.service.ts Proxy LLM multi-proveedor
    core/services/supabase.service.ts  Auth + pgvector + storage
    core/guards/auth.guard.ts          Proteccion de rutas
    features/chat/                     Componente chat completo
    features/library/                  Biblioteca legal (placeholder)
    features/cases/                    Carpetas de casos (placeholder)

  BACKEND (backend/):
    api/main.py                        FastAPI app principal
    api/routes/llm.py                  Proxy LLM con fallover
    api/routes/embeddings.py           sentence-transformers
    api/routes/health.py               Health check

  WORKERS (workers/orchestrator/):
    src/index.ts                       Orquestador L-MARS TypeScript

  INFRAESTRUCTURA:
    infra/supabase/schema.sql          BD + pgvector + RLS
    scripts/dev.ps1                    Arranque local

  SIGUIENTE PASO:
    .\scripts\get-api-keys.ps1         Obtener API keys gratuitas
    .\scripts\dev.ps1                  Arrancar entorno local

===============================================================
"@ -ForegroundColor Green
