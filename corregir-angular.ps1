# JURIS-FREE Bolivia — Correccion de archivos Angular
# Sobreescribe los archivos con errores de compilacion
# PowerShell 7+

param([string]$Ruta = "C:\proyectos\juris-free")

$fe = "$Ruta\frontend\src\app"
$ErrorActionPreference = "Continue"

function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }

Write-Host "`n  JURIS-FREE — Corrigiendo archivos Angular`n" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════
# 1. INSTALAR @supabase/supabase-js si falta
# ══════════════════════════════════════════════════════
PASO "Verificando dependencias"
Set-Location "$Ruta\frontend"
$pkg = Get-Content "package.json" -Raw
if ($pkg -notmatch "supabase") {
    Write-Host "  Instalando @supabase/supabase-js..." -ForegroundColor Yellow
    npm install @supabase/supabase-js --save --silent 2>&1 | Out-Null
    OK "@supabase/supabase-js instalado"
} else {
    OK "@supabase/supabase-js ya instalado"
}

# ══════════════════════════════════════════════════════
# 2. LEGAL MODELS
# ══════════════════════════════════════════════════════
PASO "legal.models.ts"
New-Item -ItemType Directory -Path "$fe\core\models" -Force | Out-Null
[System.IO.File]::WriteAllText("$fe\core\models\legal.models.ts", @'
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
'@)
OK "legal.models.ts"

# ══════════════════════════════════════════════════════
# 3. LLM PROXY SERVICE
# ══════════════════════════════════════════════════════
PASO "llm-proxy.service.ts"
New-Item -ItemType Directory -Path "$fe\core\services" -Force | Out-Null
[System.IO.File]::WriteAllText("$fe\core\services\llm-proxy.service.ts", @'
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
    { name: 'gemini',     model: 'gemini-2.5-flash',           priority: 1, maxRequestsPerDay: 1500  },
    { name: 'groq',       model: 'llama-3.3-70b-versatile',    priority: 2, maxRequestsPerDay: 14400 },
    { name: 'cerebras',   model: 'llama3.3-70b',               priority: 3, maxRequestsPerDay: 14400 },
    { name: 'openrouter', model: 'qwen/qwen-2.5-72b-instruct', priority: 4, maxRequestsPerDay: 200   },
    { name: 'sambanova',  model: 'Meta-Llama-3.3-70B-Instruct',priority: 5, maxRequestsPerDay: 1000  }
  ];

  chat(messages: LlmMessage[], systemPrompt?: string, preferredProvider?: string): Observable<LlmResponse> {
    const ordered = this.getOrderedProviders(preferredProvider);
    return this.tryProviders(messages, systemPrompt, ordered, 0);
  }

  private tryProviders(
    messages: LlmMessage[],
    system: string | undefined,
    providers: ProviderConfig[],
    index: number
  ): Observable<LlmResponse> {
    if (index >= providers.length) {
      return throwError(() => new Error('Todos los proveedores LLM no disponibles.'));
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

  private callBackend(
    provider: ProviderConfig,
    messages: LlmMessage[],
    system?: string
  ): Observable<LlmResponse> {
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
      provider: p.name,
      model: p.model,
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
'@)
OK "llm-proxy.service.ts"

# ══════════════════════════════════════════════════════
# 4. SUPABASE SERVICE
# ══════════════════════════════════════════════════════
PASO "supabase.service.ts"
[System.IO.File]::WriteAllText("$fe\core\services\supabase.service.ts", @'
import { Injectable } from '@angular/core';
import { createClient, SupabaseClient, User, Session } from '@supabase/supabase-js';
import { BehaviorSubject, Observable, from } from 'rxjs';
import { map } from 'rxjs/operators';
import { environment } from '../../../environments/environment';
import { LegalDocument, Conversation, ChatMessage } from '../models/legal.models';

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  private client: SupabaseClient;
  private userSubject    = new BehaviorSubject<User | null>(null);
  private sessionSubject = new BehaviorSubject<Session | null>(null);

  readonly currentUser$    = this.userSubject.asObservable();
  readonly session$        = this.sessionSubject.asObservable();
  readonly isAuthenticated$ = this.currentUser$.pipe(map(u => !!u));

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

  signInWithGoogle(): Observable<void> {
    return from(
      this.client.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.origin + '/auth/callback' }
      }).then(({ error }) => { if (error) throw error; })
    );
  }

  signInWithMagicLink(email: string): Observable<void> {
    return from(
      this.client.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: window.location.origin + '/auth/callback' }
      }).then(({ error }) => { if (error) throw error; })
    );
  }

  signOut(): Observable<void> {
    return from(
      this.client.auth.signOut().then(({ error }) => { if (error) throw error; })
    );
  }

  searchLegal(queryEmbedding: number[], area?: string, limit = 5): Observable<LegalDocument[]> {
    return from(
      this.client.rpc('match_legal_documents', {
        query_embedding: queryEmbedding,
        match_threshold: 0.7,
        match_count: limit,
        filter_area: area ?? null
      }).then(({ data, error }) => {
        if (error) throw error;
        return (data as LegalDocument[]) ?? [];
      })
    );
  }

  getConversations(userId: string): Observable<Conversation[]> {
    return from(
      this.client.from('conversations')
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
      this.client.from('conversations')
        .insert({ user_id: userId, title, area, message_count: 0 })
        .select()
        .single()
        .then(({ data, error }) => {
          if (error) throw error;
          return data as Conversation;
        })
    );
  }

  getMessages(conversationId: string): Observable<ChatMessage[]> {
    return from(
      this.client.from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true })
        .then(({ data, error }) => {
          if (error) throw error;
          return (data as ChatMessage[]) ?? [];
        })
    );
  }

  saveMessage(msg: Omit<ChatMessage, 'id' | 'timestamp'>): Observable<ChatMessage> {
    return from(
      this.client.from('messages')
        .insert(msg)
        .select()
        .single()
        .then(({ data, error }) => {
          if (error) throw error;
          return data as ChatMessage;
        })
    );
  }

  uploadCaseDocument(file: File, caseId: string, userId: string): Observable<string> {
    const path = userId + '/cases/' + caseId + '/' + file.name;
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
'@)
OK "supabase.service.ts"

# ══════════════════════════════════════════════════════
# 5. AUTH GUARD
# ══════════════════════════════════════════════════════
PASO "auth.guard.ts"
New-Item -ItemType Directory -Path "$fe\core\guards" -Force | Out-Null
[System.IO.File]::WriteAllText("$fe\core\guards\auth.guard.ts", @'
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SupabaseService } from '../services/supabase.service';
import { map, take } from 'rxjs/operators';

export const authGuard: CanActivateFn = () => {
  const supabase = inject(SupabaseService);
  const router   = inject(Router);
  return supabase.isAuthenticated$.pipe(
    take(1),
    map(isAuth => isAuth ? true : router.createUrlTree(['/chat']))
  );
};
'@)
OK "auth.guard.ts"

# ══════════════════════════════════════════════════════
# 6. CHAT COMPONENT
# ══════════════════════════════════════════════════════
PASO "chat.component.ts"
New-Item -ItemType Directory -Path "$fe\features\chat" -Force | Out-Null
[System.IO.File]::WriteAllText("$fe\features\chat\chat.component.ts", @'
import { Component, OnInit, OnDestroy, ViewChild, ElementRef, inject, signal } from '@angular/core';
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
    { value: 'penal',          label: 'Penal',          icon: '⚖' },
    { value: 'laboral',        label: 'Laboral',        icon: '👷' },
    { value: 'constitucional', label: 'Constitucional', icon: '🏛' },
    { value: 'administrativo', label: 'Administrativo', icon: '🏢' },
    { value: 'familiar',       label: 'Familiar',       icon: '👨‍👩‍👧' }
  ];

  ngOnInit(): void {
    this.messages.set([{
      id: 'welcome',
      role: 'assistant',
      timestamp: new Date(),
      content: 'Bienvenido a JURIS-FREE Bolivia. Soy tu asistente juridico especializado en derecho boliviano. Escribe tu consulta.',
      provider: 'sistema'
    }]);
    this.loadHistory();
  }

  ngOnDestroy(): void {
    this.destroy.next();
    this.destroy.complete();
  }

  sendMessage(): void {
    const text = this.inputControl.value.trim();
    if (!text || this.isLoading()) return;

    const userMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'user',
      content: text,
      timestamp: new Date()
    };

    this.messages.update(m => [...m, userMsg]);
    this.inputControl.reset();
    this.isLoading.set(true);
    this.history.push({ role: 'user', content: text });

    const assistantId = crypto.randomUUID();
    this.messages.update(m => [...m, {
      id: assistantId,
      role: 'assistant',
      content: '',
      timestamp: new Date(),
      isStreaming: true
    }]);
    this.scrollBottom();

    this.llm.chat(this.history, SYSTEM_PROMPT)
      .pipe(takeUntil(this.destroy))
      .subscribe({
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
            msg.id === assistantId
              ? { ...msg, content: 'Error: ' + err.message, isStreaming: false }
              : msg
          ));
          this.isLoading.set(false);
        }
      });
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.sendMessage();
    }
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
    } catch {
      this.history = [];
    }
  }
}
'@)
OK "chat.component.ts"

PASO "chat.component.html"
[System.IO.File]::WriteAllText("$fe\features\chat\chat.component.html", @'
<div class="chat-wrap">
  <header class="topbar">
    <div class="brand">
      <span>⚖️</span>
      <span class="brand-name">JURIS-FREE <span class="brand-bo">Bolivia</span></span>
    </div>
    <div class="topbar-right">
      @if (currentProvider()) {
        <span class="provider-tag">{{ currentProvider() }}</span>
      }
      <button class="icon-btn" (click)="clearChat()" title="Nueva consulta">+</button>
    </div>
  </header>

  <nav class="area-nav">
    @for (a of areas; track a.value) {
      <button class="area-btn" [class.active]="selectedArea() === a.value" (click)="selectedArea.set(a.value)">
        {{ a.label }}
      </button>
    }
  </nav>

  <div class="messages" #messagesEl>
    @for (msg of messages(); track msg.id) {
      <div class="msg" [class.user]="msg.role === 'user'" [class.bot]="msg.role === 'assistant'">
        @if (msg.role === 'assistant') {
          <div class="avatar">⚖</div>
        }
        <div class="bubble">
          @if (msg.isStreaming) {
            <div class="typing"><span></span><span></span><span></span></div>
          } @else {
            <div class="content">{{ msg.content }}</div>
          }
          <div class="meta">
            <span>{{ msg.timestamp | date:'HH:mm' }}</span>
            @if (msg.provider && msg.provider !== 'sistema') {
              <span class="prov">{{ msg.provider }}</span>
            }
          </div>
        </div>
        @if (msg.role === 'user') {
          <div class="avatar user-av">U</div>
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
      @if (isLoading()) { ... } @else { &rarr; }
    </button>
  </div>

  <footer class="foot">
    <span>Bolivia CPE 2009 · TCP · TSJ · Gaceta Oficial</span>
    <span>Open Source · Gratuito</span>
  </footer>
</div>
'@)
OK "chat.component.html"

PASO "chat.component.scss"
[System.IO.File]::WriteAllText("$fe\features\chat\chat.component.scss", @'
:host {
  --prim: #1a3a5c;
  --gold: #c4922a;
  --bg:   #f8f6f1;
  --surf: #ffffff;
  --bord: #e0d8c8;
  --txt:  #2c2416;
  --mut:  #7a6e5e;
  display: block;
  height: 100vh;
  font-family: Georgia, serif;
}
.chat-wrap { display:flex; flex-direction:column; height:100vh; max-width:860px; margin:0 auto; background:var(--bg); }
.topbar { display:flex; justify-content:space-between; align-items:center; padding:12px 18px; background:var(--prim); border-bottom:3px solid var(--gold); }
.brand { display:flex; align-items:center; gap:8px; color:#fff; font-size:1.1rem; font-weight:700; }
.brand-name { letter-spacing:.04em; }
.brand-bo { color:var(--gold); font-style:italic; }
.topbar-right { display:flex; align-items:center; gap:10px; }
.provider-tag { background:rgba(196,146,42,.2); border:1px solid var(--gold); color:#ffd98e; font-size:.68rem; padding:2px 9px; border-radius:20px; font-family:monospace; }
.icon-btn { background:none; border:none; color:rgba(255,255,255,.7); font-size:1.4rem; cursor:pointer; padding:2px 8px; }
.icon-btn:hover { color:#fff; }
.area-nav { display:flex; gap:5px; padding:8px 14px; background:var(--surf); border-bottom:1px solid var(--bord); overflow-x:auto; scrollbar-width:none; }
.area-nav::-webkit-scrollbar { display:none; }
.area-btn { padding:4px 12px; border:1px solid var(--bord); background:#fff; border-radius:20px; cursor:pointer; font-size:.76rem; color:var(--mut); transition:.2s; white-space:nowrap; }
.area-btn:hover { border-color:var(--prim); color:var(--prim); }
.area-btn.active { background:var(--prim); border-color:var(--prim); color:#fff; }
.messages { flex:1; overflow-y:auto; padding:18px 14px; display:flex; flex-direction:column; gap:14px; }
.msg { display:flex; gap:9px; align-items:flex-start; }
.msg.user { flex-direction:row-reverse; }
.avatar { width:34px; height:34px; border-radius:50%; background:var(--gold); display:flex; align-items:center; justify-content:center; font-size:.9rem; flex-shrink:0; }
.user-av { background:var(--prim); color:#fff; font-size:.75rem; font-weight:700; }
.bubble { max-width:76%; padding:10px 14px; border-radius:12px; }
.msg.bot .bubble { background:var(--surf); border:1px solid var(--bord); border-radius:12px 12px 12px 3px; }
.msg.user .bubble { background:var(--prim); color:#fff; border-radius:12px 12px 3px 12px; }
.content { font-size:.9rem; line-height:1.65; white-space:pre-wrap; }
.msg.bot .content { color:var(--txt); }
.meta { display:flex; gap:7px; margin-top:5px; font-size:.68rem; color:var(--mut); font-family:monospace; }
.msg.user .meta { color:rgba(255,255,255,.5); }
.prov { background:rgba(196,146,42,.15); color:var(--gold); padding:1px 6px; border-radius:4px; }
.typing { display:flex; gap:4px; padding:4px 0; }
.typing span { width:7px; height:7px; border-radius:50%; background:var(--mut); animation:blink 1.2s infinite; }
.typing span:nth-child(2) { animation-delay:.2s; }
.typing span:nth-child(3) { animation-delay:.4s; }
@keyframes blink { 0%,80%,100%{transform:scale(.7);opacity:.4} 40%{transform:scale(1);opacity:1} }
.input-row { display:flex; gap:8px; padding:12px 14px; background:var(--surf); border-top:1px solid var(--bord); }
.inp { flex:1; border:1px solid var(--bord); border-radius:10px; padding:9px 13px; font-size:.88rem; font-family:inherit; resize:none; background:var(--bg); color:var(--txt); transition:.2s; }
.inp:focus { outline:none; border-color:var(--prim); background:#fff; }
.inp:disabled { opacity:.55; }
.send-btn { width:44px; height:44px; border-radius:50%; border:none; background:var(--prim); color:#fff; font-size:1.2rem; cursor:pointer; transition:.2s; }
.send-btn:hover:not(:disabled) { background:#0f2440; transform:scale(1.07); }
.send-btn:disabled { opacity:.35; }
.foot { display:flex; justify-content:space-between; padding:5px 14px; font-size:.65rem; color:var(--mut); border-top:1px solid var(--bord); }
'@)
OK "chat.component.scss"

# ══════════════════════════════════════════════════════
# 7. COMPONENTES PLACEHOLDER (sin emojis ni caracteres especiales)
# ══════════════════════════════════════════════════════
PASO "Componentes placeholder"

$placeholders = @(
    @{ name="library";  selector="app-library";  class="LibraryComponent";  title="Biblioteca Legal";  desc="Busqueda de leyes, decretos y sentencias bolivianas" },
    @{ name="cases";    selector="app-cases";    class="CasesComponent";    title="Carpetas de Casos"; desc="Organiza tus casos con documentos y resumenes por IA" },
    @{ name="settings"; selector="app-settings"; class="SettingsComponent"; title="Configuracion";     desc="Preferencias, API keys y estadisticas de uso" }
)

foreach ($p in $placeholders) {
    New-Item -ItemType Directory -Path "$fe\features\$($p.name)" -Force | Out-Null
    $content = @"
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: '$($p.selector)',
  standalone: true,
  imports: [CommonModule],
  template: ``
    <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:80vh;gap:16px;color:#7a6e5e;font-family:Georgia,serif">
      <h2 style="color:#1a3a5c">$($p.title)</h2>
      <p>$($p.desc)</p>
      <p style="font-size:.8rem;background:#f0ede8;padding:8px 16px;border-radius:8px">Proximo modulo - en desarrollo</p>
    </div>
  ``
})
export class $($p.class) {}
"@
    [System.IO.File]::WriteAllText("$fe\features\$($p.name)\$($p.name).component.ts", $content)
    OK "$($p.name).component.ts"
}

# Auth callback
New-Item -ItemType Directory -Path "$fe\core\auth-callback" -Force | Out-Null
[System.IO.File]::WriteAllText("$fe\core\auth-callback\auth-callback.component.ts", @'
import { Component, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-auth-callback',
  standalone: true,
  imports: [CommonModule],
  template: `<div style="display:flex;align-items:center;justify-content:center;height:100vh;font-family:Georgia,serif;color:#1a3a5c">Autenticando...</div>`
})
export class AuthCallbackComponent implements OnInit {
  private router = inject(Router);
  ngOnInit(): void { setTimeout(() => this.router.navigate(['/chat']), 1500); }
}
'@)
OK "auth-callback.component.ts"

# ══════════════════════════════════════════════════════
# 8. APP CONFIG (provideHttpClient)
# ══════════════════════════════════════════════════════
PASO "app.config.ts"
[System.IO.File]::WriteAllText("$fe\app.config.ts", @'
import { ApplicationConfig } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient()
  ]
};
'@)
OK "app.config.ts"

# ══════════════════════════════════════════════════════
# RESULTADO
# ══════════════════════════════════════════════════════
Write-Host @"

===============================================================
  Archivos corregidos. Vuelve a la terminal del frontend y
  espera que Angular recompile automaticamente (watch mode).
  Si no recompila solo, ejecuta:

  cd C:\proyectos\juris-free\frontend
  ng serve --open
===============================================================
"@ -ForegroundColor Green
