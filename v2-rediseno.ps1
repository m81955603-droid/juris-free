# JURIS-FREE Bolivia v2 — Rediseno profesional + Generador de documentos Word
# PowerShell 7+ | Sin CmdletBinding

param([string]$Ruta = "C:\proyectos\juris-free")

$fe = "$Ruta\frontend\src\app"
$ErrorActionPreference = "Continue"

function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }

Write-Host "`n  JURIS-FREE Bolivia v2 — Rediseno profesional`n" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════
# 1. INSTALAR DEPENDENCIAS WORD + MARKDOWN
# ══════════════════════════════════════════════════════
PASO "Instalando dependencias"
Set-Location "$Ruta\frontend"
Write-Host "  Instalando docx (generacion Word)..." -ForegroundColor DarkCyan
npm install docx file-saver marked dompurify --save --silent 2>&1 | Out-Null
npm install @types/file-saver @types/dompurify --save-dev --silent 2>&1 | Out-Null
OK "docx + file-saver + marked instalados"

# ══════════════════════════════════════════════════════
# 2. ESTILOS GLOBALES — REDISENO PROFESIONAL
# ══════════════════════════════════════════════════════
PASO "Estilos globales — tema profesional"

[System.IO.File]::WriteAllText("$Ruta\frontend\src\styles.scss", @'
@import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;600;700&family=DM+Sans:wght@300;400;500&family=DM+Mono:wght@400;500&display=swap');

:root {
  --prim:    #0f1f35;
  --prim-2:  #1a3352;
  --prim-3:  #254a73;
  --gold:    #b8872a;
  --gold-lt: #d4a84b;
  --gold-bg: #fdf6e8;
  --bg:      #f9f8f6;
  --surf:    #ffffff;
  --surf-2:  #f4f2ee;
  --bord:    #e8e3d8;
  --bord-2:  #d4cfc4;
  --txt:     #1a1510;
  --txt-2:   #4a4438;
  --txt-3:   #7a7268;
  --red:     #c0392b;
  --green:   #1a6b3c;
  --radius:  10px;
  --shadow:  0 1px 3px rgba(15,31,53,.06), 0 4px 16px rgba(15,31,53,.04);
  --shadow-md: 0 2px 8px rgba(15,31,53,.08), 0 8px 32px rgba(15,31,53,.06);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

html, body {
  height: 100%;
  font-family: 'DM Sans', sans-serif;
  background: var(--bg);
  color: var(--txt);
  -webkit-font-smoothing: antialiased;
}

::-webkit-scrollbar { width: 5px; height: 5px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--bord-2); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--txt-3); }

::selection { background: rgba(184,135,42,.18); }
'@)
OK "styles.scss"

# ══════════════════════════════════════════════════════
# 3. APP SHELL — LAYOUT CON SIDEBAR
# ══════════════════════════════════════════════════════
PASO "App shell con sidebar navegacion"

[System.IO.File]::WriteAllText("$fe\app.component.ts", @'
import { Component, signal } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, CommonModule],
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss']
})
export class AppComponent {
  sidebarCollapsed = signal(false);

  readonly navItems = [
    { path: '/chat',      icon: 'M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z', label: 'Consulta' },
    { path: '/documents', icon: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z', label: 'Documentos' },
    { path: '/cases',     icon: 'M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z', label: 'Casos' },
    { path: '/library',   icon: 'M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253', label: 'Biblioteca' },
    { path: '/settings',  icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z', label: 'Config' }
  ];
}
'@)

[System.IO.File]::WriteAllText("$fe\app.component.html", @'
<div class="shell" [class.collapsed]="sidebarCollapsed()">

  <aside class="sidebar">
    <div class="sidebar-header">
      <div class="logo">
        <div class="logo-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1M4.22 4.22l.707.707m12.02 12.02l.707.707M1 12h1m20 0h1M4.22 19.78l.707-.707M18.95 5.05l.707-.707M12 7a5 5 0 100 10A5 5 0 0012 7z"/>
          </svg>
        </div>
        @if (!sidebarCollapsed()) {
          <div class="logo-text">
            <span class="logo-name">JURIS-FREE</span>
            <span class="logo-sub">Bolivia</span>
          </div>
        }
      </div>
      <button class="collapse-btn" (click)="sidebarCollapsed.set(!sidebarCollapsed())" [title]="sidebarCollapsed() ? 'Expandir' : 'Contraer'">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>
        </svg>
      </button>
    </div>

    <nav class="sidebar-nav">
      @for (item of navItems; track item.path) {
        <a class="nav-item" [routerLink]="item.path" routerLinkActive="active" [title]="item.label">
          <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" [attr.d]="item.icon"/>
          </svg>
          @if (!sidebarCollapsed()) {
            <span class="nav-label">{{ item.label }}</span>
          }
        </a>
      }
    </nav>

    @if (!sidebarCollapsed()) {
      <div class="sidebar-footer">
        <div class="status-dot"></div>
        <span class="status-text">Sistema activo</span>
      </div>
    }
  </aside>

  <main class="main-content">
    <router-outlet />
  </main>

</div>
'@)

[System.IO.File]::WriteAllText("$fe\app.component.scss", @'
.shell {
  display: grid;
  grid-template-columns: 220px 1fr;
  height: 100vh;
  overflow: hidden;
  transition: grid-template-columns .25s ease;

  &.collapsed { grid-template-columns: 60px 1fr; }
}

.sidebar {
  background: var(--prim);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border-right: 1px solid rgba(255,255,255,.06);
  position: relative;
  z-index: 10;
}

.sidebar-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20px 14px 16px;
  border-bottom: 1px solid rgba(255,255,255,.06);
}

.logo {
  display: flex;
  align-items: center;
  gap: 10px;
  overflow: hidden;
}

.logo-icon {
  width: 32px;
  height: 32px;
  background: var(--gold);
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;

  svg { width: 18px; height: 18px; color: white; }
}

.logo-text {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.logo-name {
  font-family: 'Playfair Display', serif;
  font-size: .82rem;
  font-weight: 700;
  color: white;
  letter-spacing: .08em;
  white-space: nowrap;
}

.logo-sub {
  font-size: .68rem;
  color: var(--gold-lt);
  letter-spacing: .1em;
  text-transform: uppercase;
}

.collapse-btn {
  background: none;
  border: none;
  cursor: pointer;
  padding: 4px;
  color: rgba(255,255,255,.35);
  border-radius: 6px;
  flex-shrink: 0;
  transition: .2s;

  svg { width: 14px; height: 14px; display: block; }
  &:hover { color: rgba(255,255,255,.7); background: rgba(255,255,255,.06); }
}

.sidebar-nav {
  flex: 1;
  padding: 12px 8px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  overflow-y: auto;
  scrollbar-width: none;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border-radius: 8px;
  text-decoration: none;
  color: rgba(255,255,255,.5);
  transition: .15s;
  white-space: nowrap;
  overflow: hidden;

  &:hover { background: rgba(255,255,255,.06); color: rgba(255,255,255,.85); }

  &.active {
    background: rgba(184,135,42,.15);
    color: var(--gold-lt);
    border-left: 2px solid var(--gold);
    padding-left: 8px;
  }
}

.nav-icon { width: 18px; height: 18px; flex-shrink: 0; }
.nav-label { font-size: .82rem; font-weight: 400; }

.sidebar-footer {
  padding: 14px 16px;
  border-top: 1px solid rgba(255,255,255,.06);
  display: flex;
  align-items: center;
  gap: 8px;
}

.status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #22c55e;
  animation: pulse 2s infinite;
  flex-shrink: 0;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: .5; }
}

.status-text { font-size: .7rem; color: rgba(255,255,255,.4); }

.main-content {
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background: var(--bg);
}
'@)
OK "App shell con sidebar"

# ══════════════════════════════════════════════════════
# 4. CHAT COMPONENT — REDISENO PROFESIONAL
# ══════════════════════════════════════════════════════
PASO "Chat component rediseñado"

[System.IO.File]::WriteAllText("$fe\features\chat\chat.component.ts", @'
import { Component, OnInit, OnDestroy, ViewChild, ElementRef, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { ChatMessage, LegalArea, LlmMessage } from '../../core/models/legal.models';
import { DocumentService } from '../../core/services/document.service';

const SYSTEM_PROMPT = `Eres JURIS-FREE, asistente juridico especializado en derecho boliviano.
Usa formato Markdown en tus respuestas: **negritas** para articulos y normas, ## para secciones, - para listas.
REGLAS:
1. Cita siempre el articulo exacto y la norma boliviana vigente.
2. Menciona jurisprudencia del TCP o TSJ cuando sea relevante (con numero de sentencia).
3. Distingue norma vigente de norma derogada.
4. Estructura: ## Base Legal -> ## Analisis -> ## Consecuencias -> ## Recomendacion.
5. NUNCA inventes articulos o sentencias.
6. Referencias: CPE 2009, Cod. Civil (Ley 12760), Cod. Penal (Ley 1768), Cod. Familiar (Ley 996), Cod. Procesal Civil (Ley 439).`;

interface QuickAction {
  label: string;
  prompt: string;
  icon: string;
}

@Component({
  selector: 'app-chat',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './chat.component.html',
  styleUrls: ['./chat.component.scss']
})
export class ChatComponent implements OnInit, OnDestroy {
  @ViewChild('messagesEl') messagesEl!: ElementRef;
  @ViewChild('inputEl') inputEl!: ElementRef;

  private llm     = inject(LlmProxyService);
  private docSvc  = inject(DocumentService);
  private destroy = new Subject<void>();

  messages        = signal<ChatMessage[]>([]);
  isLoading       = signal(false);
  selectedArea    = signal<LegalArea>('auto');
  currentProvider = signal('');
  inputText       = '';
  history: LlmMessage[] = [];
  exportingId     = signal<string | null>(null);

  readonly areas: { value: LegalArea; label: string }[] = [
    { value: 'auto',           label: 'General'        },
    { value: 'civil',          label: 'Civil'          },
    { value: 'penal',          label: 'Penal'          },
    { value: 'laboral',        label: 'Laboral'        },
    { value: 'constitucional', label: 'Constitucional' },
    { value: 'administrativo', label: 'Administrativo' },
    { value: 'familiar',       label: 'Familiar'       }
  ];

  readonly quickActions: QuickAction[] = [
    { label: 'Requisitos de divorcio',       prompt: '¿Cuáles son los requisitos para el divorcio en Bolivia según la Ley 603?',     icon: '⚖' },
    { label: 'Plazos de apelación civil',    prompt: '¿Cuáles son los plazos para interponer recurso de apelación en materia civil?', icon: '📋' },
    { label: 'Derechos del trabajador',      prompt: '¿Cuáles son los derechos laborales fundamentales en Bolivia?',                  icon: '👷' },
    { label: 'Delitos contra la propiedad',  prompt: '¿Cómo tipifica el Código Penal boliviano los delitos contra la propiedad?',     icon: '🏛' }
  ];

  ngOnInit(): void {
    this.messages.set([{
      id: 'welcome',
      role: 'assistant',
      timestamp: new Date(),
      content: `## Bienvenido a JURIS-FREE Bolivia

Soy tu asistente jurídico especializado en **derecho boliviano**. Puedo ayudarte con:

- **Consultas legales** sobre normativa boliviana vigente
- **Jurisprudencia** del TCP y Tribunal Supremo de Justicia
- **Análisis** de contratos y documentos
- **Procedimientos** judiciales y plazos procesales
- **Generación** de documentos Word profesionales

Escribe tu consulta o usa las acciones rápidas para comenzar.`,
      provider: 'sistema'
    }]);
    this.loadHistory();
  }

  ngOnDestroy(): void { this.destroy.next(); this.destroy.complete(); }

  sendMessage(text?: string): void {
    const msg = (text || this.inputText).trim();
    if (!msg || this.isLoading()) return;

    const userMsg: ChatMessage = { id: crypto.randomUUID(), role: 'user', content: msg, timestamp: new Date() };
    this.messages.update(m => [...m, userMsg]);
    this.inputText = '';
    this.isLoading.set(true);
    this.history.push({ role: 'user', content: msg });

    const assistantId = crypto.randomUUID();
    this.messages.update(m => [...m, { id: assistantId, role: 'assistant', content: '', timestamp: new Date(), isStreaming: true }]);
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
            msg.id === assistantId ? { ...msg, content: '**Error:** ' + err.message, isStreaming: false } : msg
          ));
          this.isLoading.set(false);
        }
      });
  }

  async exportToWord(msg: ChatMessage): Promise<void> {
    this.exportingId.set(msg.id);
    try {
      await this.docSvc.exportChatToWord(msg.content, 'Consulta Juridica Bolivia');
    } finally {
      this.exportingId.set(null);
    }
  }

  async exportToPdf(msg: ChatMessage): Promise<void> {
    this.exportingId.set(msg.id);
    try {
      await this.docSvc.exportChatToPdf(msg.content, 'Consulta Juridica Bolivia');
    } finally {
      this.exportingId.set(null);
    }
  }

  renderMarkdown(content: string): string {
    if (!content) return '';
    return content
      .replace(/^## (.+)$/gm, '<h3>$1</h3>')
      .replace(/^### (.+)$/gm, '<h4>$1</h4>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code>$1</code>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/(<li>.*<\/li>\n?)+/gs, '<ul>$&</ul>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/^(?!<[huc])(.+)$/gm, '$1')
      .replace(/\n/g, '<br>');
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.sendMessage(); }
  }

  clearChat(): void { this.history = []; this.messages.set([]); localStorage.removeItem('juris_history'); this.ngOnInit(); }

  private scrollBottom(): void {
    setTimeout(() => { const el = this.messagesEl?.nativeElement; if (el) el.scrollTop = el.scrollHeight; }, 80);
  }
  private saveHistory(): void { localStorage.setItem('juris_history', JSON.stringify(this.history.slice(-20))); }
  private loadHistory(): void {
    try { const s = localStorage.getItem('juris_history'); if (s) this.history = JSON.parse(s); } catch { this.history = []; }
  }
}
'@)

[System.IO.File]::WriteAllText("$fe\features\chat\chat.component.html", @'
<div class="chat-layout">

  <!-- Header -->
  <header class="chat-header">
    <div class="header-left">
      <h1 class="page-title">Consulta Jurídica</h1>
      <p class="page-sub">Derecho boliviano · CPE 2009 · TCP · TSJ</p>
    </div>
    <div class="header-right">
      @if (currentProvider()) {
        <span class="provider-pill">
          <span class="provider-dot"></span>
          {{ currentProvider() }}
        </span>
      }
      <button class="btn-ghost" (click)="clearChat()" title="Nueva consulta">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="16" height="16">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m-8-8h16"/>
        </svg>
        Nueva
      </button>
    </div>
  </header>

  <!-- Area selector -->
  <div class="area-bar">
    @for (a of areas; track a.value) {
      <button class="area-chip" [class.active]="selectedArea() === a.value" (click)="selectedArea.set(a.value)">
        {{ a.label }}
      </button>
    }
  </div>

  <!-- Messages -->
  <div class="messages-area" #messagesEl>

    <!-- Quick actions (solo al inicio) -->
    @if (messages().length <= 1) {
      <div class="quick-actions">
        <p class="quick-title">Consultas frecuentes</p>
        <div class="quick-grid">
          @for (qa of quickActions; track qa.label) {
            <button class="quick-card" (click)="sendMessage(qa.prompt)">
              <span class="quick-icon">{{ qa.icon }}</span>
              <span class="quick-label">{{ qa.label }}</span>
            </button>
          }
        </div>
      </div>
    }

    @for (msg of messages(); track msg.id) {
      <div class="message" [class.user]="msg.role === 'user'" [class.assistant]="msg.role === 'assistant'">

        @if (msg.role === 'assistant') {
          <div class="msg-avatar assistant-avatar">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="16" height="16">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1M4.22 4.22l.707.707m12.02 12.02l.707.707M1 12h1m20 0h1M4.22 19.78l.707-.707M18.95 5.05l.707-.707M12 7a5 5 0 100 10A5 5 0 0012 7z"/>
            </svg>
          </div>
        }

        <div class="msg-body">
          <div class="msg-bubble">
            @if (msg.isStreaming) {
              <div class="typing-dots"><span></span><span></span><span></span></div>
            } @else {
              <div class="msg-content" [innerHTML]="renderMarkdown(msg.content)"></div>
            }
          </div>

          @if (msg.role === 'assistant' && !msg.isStreaming && msg.provider !== 'sistema') {
            <div class="msg-actions">
              <span class="msg-time">{{ msg.timestamp | date:'HH:mm' }}</span>
              @if (msg.provider) { <span class="msg-provider">{{ msg.provider }}</span> }
              <button class="action-btn" (click)="exportToWord(msg)" [disabled]="exportingId() === msg.id" title="Exportar a Word">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="13" height="13">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                </svg>
                {{ exportingId() === msg.id ? 'Generando...' : 'Word' }}
              </button>
              <button class="action-btn" (click)="exportToPdf(msg)" title="Exportar a PDF">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="13" height="13">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                </svg>
                PDF
              </button>
            </div>
          }

          @if (msg.role === 'user') {
            <div class="msg-actions">
              <span class="msg-time">{{ msg.timestamp | date:'HH:mm' }}</span>
            </div>
          }
        </div>

        @if (msg.role === 'user') {
          <div class="msg-avatar user-avatar">U</div>
        }

      </div>
    }
  </div>

  <!-- Input -->
  <div class="input-area">
    <div class="input-wrapper">
      <textarea
        #inputEl
        class="chat-input"
        [(ngModel)]="inputText"
        placeholder="Escribe tu consulta jurídica... (Enter para enviar, Shift+Enter para nueva línea)"
        rows="1"
        [disabled]="isLoading()"
        (keydown)="onKeydown($event)"
        (input)="$any($event.target).style.height = 'auto'; $any($event.target).style.height = $any($event.target).scrollHeight + 'px'">
      </textarea>
      <button class="send-btn" (click)="sendMessage()" [disabled]="isLoading() || !inputText.trim()">
        @if (isLoading()) {
          <div class="send-spinner"></div>
        } @else {
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 19V5m0 0l-7 7m7-7l7 7"/>
          </svg>
        }
      </button>
    </div>
    <p class="input-hint">Basado en CPE 2009, Ley 12760, Ley 1768, Ley 996, Ley 439 y jurisprudencia del TCP · TSJ</p>
  </div>

</div>
'@)

[System.IO.File]::WriteAllText("$fe\features\chat\chat.component.scss", @'
:host { display:flex; flex-direction:column; height:100vh; overflow:hidden; }

.chat-layout { display:flex; flex-direction:column; height:100vh; overflow:hidden; background:var(--bg); }

/* Header */
.chat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 24px;
  background: var(--surf);
  border-bottom: 1px solid var(--bord);

  .header-left { display:flex; flex-direction:column; gap:2px; }
  .page-title { font-family:"Playfair Display",serif; font-size:1.1rem; font-weight:600; color:var(--txt); }
  .page-sub { font-size:.72rem; color:var(--txt-3); letter-spacing:.03em; }
  .header-right { display:flex; align-items:center; gap:10px; }
}

.provider-pill {
  display: flex;
  align-items: center;
  gap: 6px;
  background: var(--gold-bg);
  border: 1px solid rgba(184,135,42,.2);
  color: var(--gold);
  font-size: .7rem;
  padding: 4px 10px;
  border-radius: 20px;
  font-family: 'DM Mono', monospace;
  letter-spacing: .04em;
}

.provider-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--gold);
  animation: glow 1.5s infinite;
}

@keyframes glow { 0%,100%{opacity:1} 50%{opacity:.4} }

.btn-ghost {
  display: flex;
  align-items: center;
  gap: 6px;
  background: none;
  border: 1px solid var(--bord);
  color: var(--txt-2);
  font-size: .78rem;
  padding: 6px 12px;
  border-radius: 8px;
  cursor: pointer;
  transition: .15s;
  font-family: 'DM Sans', sans-serif;

  &:hover { background: var(--surf-2); border-color: var(--bord-2); color: var(--txt); }
}

/* Area bar */
.area-bar {
  display: flex;
  gap: 4px;
  padding: 10px 24px;
  background: var(--surf);
  border-bottom: 1px solid var(--bord);
  overflow-x: auto;
  scrollbar-width: none;

  &::-webkit-scrollbar { display:none; }
}

.area-chip {
  padding: 5px 14px;
  border: 1px solid var(--bord);
  background: transparent;
  border-radius: 20px;
  font-size: .75rem;
  color: var(--txt-3);
  cursor: pointer;
  white-space: nowrap;
  transition: .15s;
  font-family: 'DM Sans', sans-serif;

  &:hover { border-color: var(--prim-3); color: var(--prim); }
  &.active { background: var(--prim); border-color: var(--prim); color: white; }
}

/* Messages */
.messages-area {
  flex: 1;
  overflow-y: auto;
  padding: 24px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* Quick actions */
.quick-actions {
  margin: 8px 0 16px;
}

.quick-title {
  font-size: .75rem;
  color: var(--txt-3);
  letter-spacing: .05em;
  text-transform: uppercase;
  margin-bottom: 10px;
}

.quick-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 8px;
}

.quick-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 14px;
  background: var(--surf);
  border: 1px solid var(--bord);
  border-radius: 10px;
  cursor: pointer;
  text-align: left;
  transition: .15s;
  font-family: 'DM Sans', sans-serif;

  &:hover { border-color: var(--prim-3); box-shadow: var(--shadow); transform: translateY(-1px); }
}

.quick-icon { font-size: 1.1rem; flex-shrink: 0; }
.quick-label { font-size: .8rem; color: var(--txt-2); line-height: 1.3; }

/* Message */
.message {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  animation: fadeIn .2s ease;

  &.user { flex-direction: row-reverse; }
}

@keyframes fadeIn { from { opacity:0; transform:translateY(6px); } to { opacity:1; transform:none; } }

.msg-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  margin-top: 2px;
}

.assistant-avatar {
  background: var(--prim);
  color: var(--gold-lt);
  border: 1px solid rgba(184,135,42,.2);
}

.user-avatar {
  background: var(--surf-2);
  border: 1px solid var(--bord);
  color: var(--txt-2);
  font-size: .72rem;
  font-weight: 500;
}

.msg-body { flex: 1; max-width: 78%; display: flex; flex-direction: column; gap: 6px; }
.message.user .msg-body { align-items: flex-end; }

.msg-bubble {
  padding: 12px 16px;
  border-radius: 12px;
  line-height: 1.65;

  .message.assistant & {
    background: var(--surf);
    border: 1px solid var(--bord);
    border-radius: 2px 12px 12px 12px;
    box-shadow: var(--shadow);
  }

  .message.user & {
    background: var(--prim);
    color: white;
    border-radius: 12px 2px 12px 12px;
  }
}

.msg-content {
  font-size: .88rem;
  color: var(--txt);

  ::ng-deep {
    h3 { font-family:'Playfair Display',serif; font-size:.95rem; font-weight:600; color:var(--prim); margin:14px 0 6px; border-bottom:1px solid var(--bord); padding-bottom:4px; }
    h4 { font-size:.85rem; font-weight:500; color:var(--prim-2); margin:10px 0 4px; }
    strong { color:var(--prim); font-weight:500; }
    code { font-family:'DM Mono',monospace; font-size:.8em; background:var(--surf-2); padding:1px 5px; border-radius:4px; color:var(--prim-2); }
    ul { padding-left:18px; margin:6px 0; }
    li { margin:3px 0; }
    p { margin:6px 0; }
    em { color:var(--txt-2); }
  }
}

.message.user .msg-content { color:white; }
.message.user .msg-content ::ng-deep strong { color:rgba(255,255,255,.9); }

.msg-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 2px;
}

.msg-time { font-size: .68rem; color: var(--txt-3); font-family:'DM Mono',monospace; }
.msg-provider { font-size: .68rem; color: var(--gold); background: var(--gold-bg); padding: 1px 6px; border-radius: 4px; font-family:'DM Mono',monospace; }

.action-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  background: none;
  border: 1px solid var(--bord);
  color: var(--txt-3);
  font-size: .7rem;
  padding: 3px 8px;
  border-radius: 6px;
  cursor: pointer;
  transition: .15s;
  font-family: 'DM Sans', sans-serif;

  &:hover { background: var(--surf-2); color: var(--prim); border-color: var(--bord-2); }
  &:disabled { opacity: .5; cursor: not-allowed; }
}

/* Typing */
.typing-dots { display:flex; gap:4px; padding:4px 0; }
.typing-dots span { width:6px; height:6px; border-radius:50%; background:var(--bord-2); animation:dots 1.2s infinite; }
.typing-dots span:nth-child(2) { animation-delay:.2s; }
.typing-dots span:nth-child(3) { animation-delay:.4s; }
@keyframes dots { 0%,80%,100%{transform:scale(.7);opacity:.4} 40%{transform:scale(1);opacity:1} }

/* Input */
.input-area {
  padding: 16px 24px 20px;
  background: var(--surf);
  border-top: 1px solid var(--bord);
}

.input-wrapper {
  display: flex;
  align-items: flex-end;
  gap: 10px;
  background: var(--bg);
  border: 1.5px solid var(--bord);
  border-radius: 12px;
  padding: 10px 10px 10px 16px;
  transition: border-color .2s;

  &:focus-within { border-color: var(--prim-3); background: white; }
}

.chat-input {
  flex: 1;
  border: none;
  background: none;
  font-size: .88rem;
  font-family: 'DM Sans', sans-serif;
  color: var(--txt);
  resize: none;
  outline: none;
  max-height: 120px;
  line-height: 1.5;

  &::placeholder { color: var(--txt-3); }
  &:disabled { opacity: .55; }
}

.send-btn {
  width: 34px;
  height: 34px;
  border-radius: 8px;
  border: none;
  background: var(--prim);
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: .15s;

  &:hover:not(:disabled) { background: var(--prim-2); transform: scale(1.04); }
  &:disabled { opacity: .35; cursor: not-allowed; }
}

.send-spinner {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255,255,255,.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin .7s linear infinite;
}

@keyframes spin { to { transform: rotate(360deg); } }

.input-hint { font-size: .65rem; color: var(--txt-3); margin-top: 8px; text-align: center; }
'@)
OK "Chat component rediseñado"

# ══════════════════════════════════════════════════════
# 5. DOCUMENT SERVICE — GENERADOR WORD + PDF
# ══════════════════════════════════════════════════════
PASO "Document Service (Word + PDF)"

[System.IO.File]::WriteAllText("$fe\core\services\document.service.ts", @'
import { Injectable } from '@angular/core';
import {
  Document, Paragraph, TextRun, HeadingLevel,
  AlignmentType, BorderStyle, PageBreak,
  Table, TableRow, TableCell, WidthType,
  Header, Footer, PageNumber, NumberFormat,
  Packer
} from 'docx';
import { saveAs } from 'file-saver';

export interface DocumentData {
  titulo: string;
  subtitulo?: string;
  ciudad?: string;
  fecha?: string;
  contenido: string;
  abogado?: string;
  matricula?: string;
}

@Injectable({ providedIn: 'root' })
export class DocumentService {

  /**
   * Exporta el contenido del chat a un documento Word profesional
   */
  async exportChatToWord(markdownContent: string, titulo: string): Promise<void> {
    const paragraphs = this.parseMarkdownToDocx(markdownContent);
    const doc = this.buildWordDocument({
      titulo,
      ciudad: 'La Paz',
      fecha: new Date().toLocaleDateString('es-BO', { day: 'numeric', month: 'long', year: 'numeric' }),
      contenido: markdownContent
    }, paragraphs);

    const buffer = await Packer.toBlob(doc);
    const filename = titulo.replace(/\s+/g, '_').toLowerCase() + '_' + new Date().toISOString().slice(0,10) + '.docx';
    saveAs(buffer, filename);
  }

  /**
   * Genera un documento legal formal (demanda, contrato, memorial)
   */
  async generateLegalDocument(data: DocumentData): Promise<void> {
    const paragraphs = this.parseMarkdownToDocx(data.contenido);
    const doc = this.buildWordDocument(data, paragraphs);
    const buffer = await Packer.toBlob(doc);
    const filename = data.titulo.replace(/\s+/g, '_').toLowerCase() + '.docx';
    saveAs(buffer, filename);
  }

  /**
   * Export simple a PDF via impresion del navegador
   */
  async exportChatToPdf(markdownContent: string, titulo: string): Promise<void> {
    const html = this.markdownToHtml(markdownContent);
    const win = window.open('', '_blank');
    if (!win) return;

    win.document.write(`
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>${titulo}</title>
        <style>
          @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;600;700&family=DM+Sans:wght@300;400;500&display=swap');
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: 'DM Sans', sans-serif; font-size: 11pt; line-height: 1.7; color: #1a1510; padding: 2cm 2.5cm; }
          .header { border-bottom: 2px solid #0f1f35; padding-bottom: 14px; margin-bottom: 24px; display: flex; justify-content: space-between; align-items: flex-end; }
          .logo-area h1 { font-family: 'Playfair Display', serif; font-size: 16pt; color: #0f1f35; }
          .logo-area p { font-size: 8pt; color: #7a7268; letter-spacing: .08em; text-transform: uppercase; }
          .doc-meta { text-align: right; font-size: 9pt; color: #7a7268; }
          h2 { font-family: 'Playfair Display', serif; font-size: 13pt; color: #0f1f35; margin: 18px 0 8px; border-bottom: 1px solid #e8e3d8; padding-bottom: 4px; }
          h3 { font-size: 11pt; font-weight: 500; color: #1a3352; margin: 14px 0 6px; }
          p { margin: 6px 0; }
          strong { color: #0f1f35; font-weight: 500; }
          code { font-family: monospace; background: #f4f2ee; padding: 1px 4px; border-radius: 3px; font-size: 9pt; }
          ul { padding-left: 18px; margin: 6px 0; }
          li { margin: 3px 0; }
          .footer { margin-top: 32px; border-top: 1px solid #e8e3d8; padding-top: 10px; font-size: 8pt; color: #7a7268; text-align: center; }
          @media print { body { padding: 1cm 1.5cm; } }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="logo-area">
            <h1>JURIS-FREE Bolivia</h1>
            <p>Sistema Juridico Inteligente · Open Source</p>
          </div>
          <div class="doc-meta">
            <p>${titulo}</p>
            <p>${new Date().toLocaleDateString('es-BO', { day: 'numeric', month: 'long', year: 'numeric' })}</p>
          </div>
        </div>
        <div class="content">${html}</div>
        <div class="footer">
          Generado por JURIS-FREE Bolivia · Este documento es de caracter informativo. No reemplaza el criterio profesional del abogado.
        </div>
        <script>window.onload = () => { window.print(); }<\/script>
      </body>
      </html>
    `);
    win.document.close();
  }

  private buildWordDocument(data: DocumentData, paragraphs: Paragraph[]): Document {
    const date = data.fecha || new Date().toLocaleDateString('es-BO', { day: 'numeric', month: 'long', year: 'numeric' });
    const city = data.ciudad || 'La Paz';

    return new Document({
      creator: 'JURIS-FREE Bolivia',
      title: data.titulo,
      description: 'Documento juridico generado por JURIS-FREE Bolivia',
      styles: {
        default: {
          document: {
            run: { font: 'Calibri', size: 22, color: '1a1510' },
            paragraph: { spacing: { after: 160, line: 280, lineRule: 'auto' } }
          }
        }
      },
      sections: [{
        properties: {
          page: {
            margin: { top: 1440, right: 1440, bottom: 1440, left: 1800 },
            size: { width: 12240, height: 15840 }
          }
        },
        headers: {
          default: new Header({
            children: [
              new Paragraph({
                children: [
                  new TextRun({ text: 'JURIS-FREE Bolivia', font: 'Calibri', size: 16, color: '0f1f35', bold: true }),
                  new TextRun({ text: '  ·  ' + data.titulo, font: 'Calibri', size: 16, color: '7a7268' })
                ],
                border: { bottom: { color: '0f1f35', size: 6, style: BorderStyle.SINGLE, space: 4 } }
              })
            ]
          })
        },
        footers: {
          default: new Footer({
            children: [
              new Paragraph({
                children: [
                  new TextRun({ text: city + ', ' + date + '   |   Pág. ', font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ children: [PageNumber.CURRENT], font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ text: ' de ', font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ children: [PageNumber.TOTAL_PAGES], font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ text: '   |   JURIS-FREE Bolivia — Documento informativo', font: 'Calibri', size: 16, color: 'b8b0a0', italics: true })
                ],
                alignment: AlignmentType.CENTER,
                border: { top: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 4 } }
              })
            ]
          })
        },
        children: [
          new Paragraph({
            children: [
              new TextRun({ text: data.titulo, font: 'Calibri', size: 36, bold: true, color: '0f1f35' })
            ],
            heading: HeadingLevel.TITLE,
            spacing: { before: 0, after: 240 }
          }),
          ...(data.subtitulo ? [new Paragraph({
            children: [new TextRun({ text: data.subtitulo, font: 'Calibri', size: 24, color: '4a4438', italics: true })],
            spacing: { after: 120 }
          })] : []),
          new Paragraph({
            children: [
              new TextRun({ text: city + ', ', font: 'Calibri', size: 20, color: '7a7268' }),
              new TextRun({ text: date, font: 'Calibri', size: 20, color: '7a7268', bold: true })
            ],
            spacing: { after: 480 },
            border: { bottom: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 8 } }
          }),
          ...paragraphs,
          new Paragraph({
            children: [new TextRun({ text: '', size: 22 })],
            spacing: { before: 480, after: 0 },
            border: { top: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 8 } }
          }),
          new Paragraph({
            children: [
              new TextRun({ text: 'Generado por JURIS-FREE Bolivia', font: 'Calibri', size: 16, color: 'b8b0a0', italics: true })
            ],
            alignment: AlignmentType.CENTER
          }),
          new Paragraph({
            children: [
              new TextRun({ text: 'Este documento es de carácter informativo. No reemplaza el criterio y responsabilidad profesional del abogado habilitado.', font: 'Calibri', size: 16, color: 'b8b0a0', italics: true })
            ],
            alignment: AlignmentType.CENTER,
            spacing: { after: 0 }
          })
        ]
      }]
    });
  }

  private parseMarkdownToDocx(markdown: string): Paragraph[] {
    const lines = markdown.split('\n');
    const paragraphs: Paragraph[] = [];

    for (const line of lines) {
      if (!line.trim()) {
        paragraphs.push(new Paragraph({ children: [new TextRun({ text: '' })], spacing: { after: 80 } }));
        continue;
      }

      if (line.startsWith('## ')) {
        paragraphs.push(new Paragraph({
          children: [new TextRun({ text: line.replace('## ', ''), font: 'Calibri', size: 28, bold: true, color: '0f1f35' })],
          heading: HeadingLevel.HEADING_1,
          spacing: { before: 360, after: 160 },
          border: { bottom: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 4 } }
        }));
        continue;
      }

      if (line.startsWith('### ')) {
        paragraphs.push(new Paragraph({
          children: [new TextRun({ text: line.replace('### ', ''), font: 'Calibri', size: 24, bold: true, color: '1a3352' })],
          heading: HeadingLevel.HEADING_2,
          spacing: { before: 240, after: 120 }
        }));
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('* ')) {
        const text = line.replace(/^[-*] /, '');
        paragraphs.push(new Paragraph({
          children: this.parseInlineMarkdown(text),
          bullet: { level: 0 },
          spacing: { after: 80 }
        }));
        continue;
      }

      paragraphs.push(new Paragraph({
        children: this.parseInlineMarkdown(line),
        spacing: { after: 120 }
      }));
    }

    return paragraphs;
  }

  private parseInlineMarkdown(text: string): TextRun[] {
    const runs: TextRun[] = [];
    const regex = /\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|(.+?)(?=\*\*|\*|`|$)/g;
    let match;

    while ((match = regex.exec(text)) !== null) {
      if (!match[0]) continue;

      if (match[1]) {
        runs.push(new TextRun({ text: match[1], font: 'Calibri', size: 22, bold: true, color: '0f1f35' }));
      } else if (match[2]) {
        runs.push(new TextRun({ text: match[2], font: 'Calibri', size: 22, italics: true, color: '4a4438' }));
      } else if (match[3]) {
        runs.push(new TextRun({ text: match[3], font: 'Courier New', size: 20, color: '1a3352' }));
      } else if (match[4]) {
        runs.push(new TextRun({ text: match[4], font: 'Calibri', size: 22, color: '1a1510' }));
      }
    }

    if (runs.length === 0) {
      runs.push(new TextRun({ text, font: 'Calibri', size: 22, color: '1a1510' }));
    }

    return runs;
  }

  private markdownToHtml(markdown: string): string {
    return markdown
      .replace(/^## (.+)$/gm, '<h2>$1</h2>')
      .replace(/^### (.+)$/gm, '<h3>$1</h3>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code>$1</code>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/(<li>.*<\/li>\n?)+/gs, '<ul>$&</ul>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br>');
  }
}
'@)
OK "document.service.ts (Word + PDF)"

# ══════════════════════════════════════════════════════
# 6. DOCUMENTS PAGE — GENERADOR DE DOCUMENTOS LEGALES
# ══════════════════════════════════════════════════════
PASO "Pagina generador de documentos"

New-Item -ItemType Directory -Path "$fe\features\documents" -Force | Out-Null

[System.IO.File]::WriteAllText("$fe\features\documents\documents.component.ts", @'
import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { DocumentService } from '../../core/services/document.service';

interface DocumentTemplate {
  id: string;
  nombre: string;
  descripcion: string;
  icon: string;
  campos: Campo[];
  systemPrompt: string;
}

interface Campo {
  id: string;
  label: string;
  tipo: 'text' | 'textarea' | 'select' | 'date';
  placeholder?: string;
  opciones?: string[];
  requerido?: boolean;
}

@Component({
  selector: 'app-documents',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './documents.component.html',
  styleUrls: ['./documents.component.scss']
})
export class DocumentsComponent {
  private llm    = inject(LlmProxyService);
  private docSvc = inject(DocumentService);

  selectedTemplate = signal<DocumentTemplate | null>(null);
  formData: Record<string, string> = {};
  isGenerating = signal(false);
  generatedContent = signal('');
  step = signal<'select' | 'form' | 'preview'>('select');

  readonly templates: DocumentTemplate[] = [
    {
      id: 'demanda-civil',
      nombre: 'Demanda Civil',
      descripcion: 'Demanda ordinaria civil según Ley 439',
      icon: '⚖',
      campos: [
        { id: 'demandante', label: 'Nombre del demandante', tipo: 'text', placeholder: 'Nombre completo', requerido: true },
        { id: 'demandado',  label: 'Nombre del demandado',  tipo: 'text', placeholder: 'Nombre completo', requerido: true },
        { id: 'objeto',     label: 'Objeto de la demanda',  tipo: 'textarea', placeholder: 'Describe el objeto de la demanda...', requerido: true },
        { id: 'hechos',     label: 'Hechos',                tipo: 'textarea', placeholder: 'Describe los hechos cronologicamente...', requerido: true },
        { id: 'juzgado',    label: 'Juzgado',               tipo: 'text', placeholder: 'Juzgado de Partido en lo Civil y Comercial N°...'},
        { id: 'ciudad',     label: 'Ciudad',                tipo: 'select', opciones: ['La Paz','Cochabamba','Santa Cruz','Oruro','Potosi','Sucre','Tarija','Trinidad','Cobija'] }
      ],
      systemPrompt: 'Redacta una demanda civil formal y profesional para Bolivia según la Ley 439 (Codigo Procesal Civil). Incluye: encabezado formal con otorosi, seccion de hechos, fundamentos de derecho con articulos especificos, petitorio claro. Usa lenguaje juridico boliviano formal.'
    },
    {
      id: 'contrato-compraventa',
      nombre: 'Contrato de Compraventa',
      descripcion: 'Contrato de compraventa de bien inmueble o mueble',
      icon: '📋',
      campos: [
        { id: 'vendedor',   label: 'Vendedor',        tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'comprador',  label: 'Comprador',       tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'bien',       label: 'Bien objeto del contrato', tipo: 'textarea', placeholder: 'Describe el bien detalladamente...', requerido: true },
        { id: 'precio',     label: 'Precio (Bs.)',    tipo: 'text', placeholder: '0.00', requerido: true },
        { id: 'forma-pago', label: 'Forma de pago',  tipo: 'select', opciones: ['Contado','En cuotas','Transferencia bancaria','A credito'] },
        { id: 'ciudad',     label: 'Ciudad',          tipo: 'select', opciones: ['La Paz','Cochabamba','Santa Cruz','Oruro','Potosi','Sucre','Tarija','Trinidad','Cobija'] }
      ],
      systemPrompt: 'Redacta un contrato de compraventa formal y completo para Bolivia segun el Codigo Civil (Ley 12760). Incluye: identificacion de las partes, objeto del contrato, precio y forma de pago, obligaciones de ambas partes, clausulas de garantia, clausula de saneamiento por eviccion, resolucion de controversias, firmas. Usa terminologia juridica boliviana correcta.'
    },
    {
      id: 'poder-notarial',
      nombre: 'Poder Notarial',
      descripcion: 'Poder especial o general para representacion legal',
      icon: '🏛',
      campos: [
        { id: 'poderdante', label: 'Poderdante (quien otorga)', tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'apoderado',  label: 'Apoderado (quien recibe)',  tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'tipo',       label: 'Tipo de poder',            tipo: 'select', opciones: ['Poder Especial','Poder General','Poder Especial Amplio'] },
        { id: 'facultades', label: 'Facultades otorgadas',     tipo: 'textarea', placeholder: 'Describe las facultades especificas...', requerido: true },
        { id: 'vigencia',   label: 'Vigencia',                 tipo: 'select', opciones: ['Sin fecha de vencimiento','1 año','2 años','Hasta revocacion expresa'] }
      ],
      systemPrompt: 'Redacta un poder notarial formal para Bolivia segun el Codigo Civil boliviano. Incluye: identificacion completa del poderdante y apoderado, tipo de poder, facultades otorgadas de manera clara y especifica, clausula de ratificacion, indicacion de que se otorga ante Notario de Fe Publica. Usa el lenguaje notarial boliviano correcto.'
    },
    {
      id: 'memorial',
      nombre: 'Memorial Judicial',
      descripcion: 'Memorial de solicitud o apelacion ante organo judicial',
      icon: '📄',
      campos: [
        { id: 'solicitante', label: 'Solicitante',        tipo: 'text', placeholder: 'Nombre completo', requerido: true },
        { id: 'autoridad',   label: 'Autoridad destinataria', tipo: 'text', placeholder: 'Juez/Tribunal destinatario', requerido: true },
        { id: 'expediente',  label: 'N° de Expediente',   tipo: 'text', placeholder: 'Número de expediente' },
        { id: 'objeto',      label: 'Objeto del memorial',tipo: 'textarea', placeholder: 'Describe lo que solicitas...', requerido: true },
        { id: 'fundamentos', label: 'Fundamentos',        tipo: 'textarea', placeholder: 'Base legal y argumental...' }
      ],
      systemPrompt: 'Redacta un memorial judicial boliviano formal y profesional. Incluye: encabezado correcto con autoridad, identificacion del solicitante, causa/expediente, otrosiDigo si corresponde, fundamentos de hecho y derecho con articulos del Codigo Procesal Civil boliviano (Ley 439), petitorio especifico y claro, formula de peticion boliviana estandar. Usa lenguaje juridico procesal boliviano.'
    },
    {
      id: 'contrato-trabajo',
      nombre: 'Contrato de Trabajo',
      descripcion: 'Contrato laboral según Ley General del Trabajo',
      icon: '👷',
      campos: [
        { id: 'empleador',  label: 'Empleador/Empresa',   tipo: 'text', placeholder: 'Nombre o razon social', requerido: true },
        { id: 'trabajador', label: 'Trabajador',           tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'cargo',      label: 'Cargo/Funcion',        tipo: 'text', placeholder: 'Cargo a desempenar', requerido: true },
        { id: 'salario',    label: 'Salario mensual (Bs)', tipo: 'text', placeholder: '0.00', requerido: true },
        { id: 'jornada',    label: 'Jornada',              tipo: 'select', opciones: ['8 horas diarias / 48 semanales','Tiempo parcial','Por obra o tarea'] },
        { id: 'modalidad',  label: 'Modalidad',            tipo: 'select', opciones: ['Indefinido','A plazo fijo','A prueba (90 dias)'] }
      ],
      systemPrompt: 'Redacta un contrato de trabajo formal para Bolivia segun la Ley General del Trabajo y su Decreto Reglamentario. Incluye: identificacion de las partes, objeto del contrato, jornada de trabajo, remuneracion con desglose de beneficios sociales (aguinaldo, vacaciones, AFP, CNS), obligaciones del trabajador y empleador, causales de rescision, ley aplicable. Cita los articulos especificos de la LGT boliviana.'
    },
    {
      id: 'denuncia-penal',
      nombre: 'Denuncia Penal',
      descripcion: 'Denuncia formal ante el Ministerio Publico',
      icon: '🚨',
      campos: [
        { id: 'denunciante', label: 'Denunciante',         tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'denunciado',  label: 'Denunciado (si conoce)', tipo: 'text', placeholder: 'Nombre o descripcion' },
        { id: 'delito',      label: 'Delito presunto',     tipo: 'text', placeholder: 'Ej: estafa, robo, lesiones...', requerido: true },
        { id: 'hechos',      label: 'Descripcion de hechos', tipo: 'textarea', placeholder: 'Relata los hechos cronologicamente con fechas, lugares y circunstancias...', requerido: true },
        { id: 'pruebas',     label: 'Pruebas disponibles', tipo: 'textarea', placeholder: 'Describe las pruebas que puedes presentar...' }
      ],
      systemPrompt: 'Redacta una denuncia penal formal para Bolivia ante el Ministerio Publico segun el Codigo de Procedimiento Penal (Ley 1970). Incluye: identificacion del denunciante, descripcion clara de los hechos, tipificacion del delito segun el Codigo Penal boliviano (Ley 1768) con los articulos correspondientes, solicitud de investigacion, ofrecimiento de pruebas. Usa lenguaje juridico penal boliviano.'
    }
  ];

  selectTemplate(template: DocumentTemplate): void {
    this.selectedTemplate.set(template);
    this.formData = {};
    template.campos.forEach(c => this.formData[c.id] = '');
    this.generatedContent.set('');
    this.step.set('form');
  }

  async generateDocument(): Promise<void> {
    const template = this.selectedTemplate();
    if (!template) return;

    this.isGenerating.set(true);
    this.step.set('preview');

    const fieldsSummary = template.campos
      .map(c => `${c.label}: ${this.formData[c.id] || '(no especificado)'}`)
      .join('\n');

    const prompt = `${template.systemPrompt}

DATOS DEL DOCUMENTO:
${fieldsSummary}

Genera el documento completo, formal y listo para usar en Bolivia.`;

    try {
      this.llm.chat([{ role: 'user', content: prompt }]).subscribe({
        next: resp => {
          this.generatedContent.set(resp.content);
          this.isGenerating.set(false);
        },
        error: err => {
          this.generatedContent.set('**Error al generar:** ' + err.message);
          this.isGenerating.set(false);
        }
      });
    } catch (err) {
      this.isGenerating.set(false);
    }
  }

  async downloadWord(): Promise<void> {
    const template = this.selectedTemplate();
    if (!template || !this.generatedContent()) return;
    await this.docSvc.generateLegalDocument({
      titulo: template.nombre,
      ciudad: this.formData['ciudad'] || 'La Paz',
      contenido: this.generatedContent()
    });
  }

  async downloadPdf(): Promise<void> {
    const template = this.selectedTemplate();
    if (!template || !this.generatedContent()) return;
    await this.docSvc.exportChatToPdf(this.generatedContent(), template.nombre);
  }

  renderMarkdown(content: string): string {
    if (!content) return '';
    return content
      .replace(/^## (.+)$/gm, '<h3>$1</h3>')
      .replace(/^### (.+)$/gm, '<h4>$1</h4>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code>$1</code>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/(<li>.*<\/li>\n?)+/gs, '<ul>$&</ul>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br>');
  }

  backToTemplates(): void { this.step.set('select'); this.selectedTemplate.set(null); }
  backToForm(): void { this.step.set('form'); }
}
'@)
OK "documents.component.ts"

[System.IO.File]::WriteAllText("$fe\features\documents\documents.component.html", @'
<div class="docs-layout">

  <header class="page-header">
    <div>
      <h1 class="page-title">Generador de Documentos</h1>
      <p class="page-sub">Documentos legales bolivianos profesionales en Word y PDF</p>
    </div>
    @if (step() !== 'select') {
      <button class="btn-ghost" (click)="backToTemplates()">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="15" height="15">
          <path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
        </svg>
        Volver
      </button>
    }
  </header>

  <!-- PASO 1: Seleccion de plantilla -->
  @if (step() === 'select') {
    <div class="templates-grid">
      @for (t of templates; track t.id) {
        <button class="template-card" (click)="selectTemplate(t)">
          <span class="tmpl-icon">{{ t.icon }}</span>
          <div class="tmpl-info">
            <h3 class="tmpl-name">{{ t.nombre }}</h3>
            <p class="tmpl-desc">{{ t.descripcion }}</p>
          </div>
          <svg class="tmpl-arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="16" height="16">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
          </svg>
        </button>
      }
    </div>
  }

  <!-- PASO 2: Formulario -->
  @if (step() === 'form') {
    <div class="form-container">
      <div class="form-header">
        <span class="form-icon">{{ selectedTemplate()?.icon }}</span>
        <div>
          <h2 class="form-title">{{ selectedTemplate()?.nombre }}</h2>
          <p class="form-sub">Completa los datos para generar el documento</p>
        </div>
      </div>

      <div class="form-fields">
        @for (campo of selectedTemplate()?.campos || []; track campo.id) {
          <div class="field-group">
            <label class="field-label">
              {{ campo.label }}
              @if (campo.requerido) { <span class="required">*</span> }
            </label>

            @if (campo.tipo === 'textarea') {
              <textarea class="field-input field-textarea" [(ngModel)]="formData[campo.id]" [placeholder]="campo.placeholder || ''" rows="3"></textarea>
            } @else if (campo.tipo === 'select') {
              <select class="field-input field-select" [(ngModel)]="formData[campo.id]">
                <option value="">Seleccionar...</option>
                @for (op of campo.opciones; track op) {
                  <option [value]="op">{{ op }}</option>
                }
              </select>
            } @else {
              <input class="field-input" [type]="campo.tipo" [(ngModel)]="formData[campo.id]" [placeholder]="campo.placeholder || ''">
            }
          </div>
        }
      </div>

      <div class="form-actions">
        <button class="btn-primary" (click)="generateDocument()" [disabled]="isGenerating()">
          @if (isGenerating()) {
            <div class="btn-spinner"></div> Generando...
          } @else {
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="16" height="16">
              <path stroke-linecap="round" stroke-linejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z"/>
            </svg>
            Generar documento con IA
          }
        </button>
      </div>
    </div>
  }

  <!-- PASO 3: Preview + Descarga -->
  @if (step() === 'preview') {
    <div class="preview-container">
      <div class="preview-toolbar">
        <button class="btn-ghost" (click)="backToForm()">Editar datos</button>
        <div class="download-btns">
          @if (!isGenerating() && generatedContent()) {
            <button class="btn-download word" (click)="downloadWord()">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="15" height="15">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
              </svg>
              Descargar Word
            </button>
            <button class="btn-download pdf" (click)="downloadPdf()">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="15" height="15">
                <path stroke-linecap="round" stroke-linejoin="round" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
              </svg>
              Descargar PDF
            </button>
          }
        </div>
      </div>

      <div class="preview-doc">
        @if (isGenerating()) {
          <div class="generating-state">
            <div class="gen-spinner"></div>
            <p>Generando documento con IA...</p>
            <p class="gen-sub">Redactando con normativa boliviana vigente</p>
          </div>
        } @else {
          <div class="doc-content" [innerHTML]="renderMarkdown(generatedContent())"></div>
        }
      </div>
    </div>
  }

</div>
'@)

[System.IO.File]::WriteAllText("$fe\features\documents\documents.component.scss", @'
:host { display:flex; flex-direction:column; height:100vh; overflow:hidden; }

.docs-layout { display:flex; flex-direction:column; height:100vh; overflow:hidden; background:var(--bg); }

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 24px;
  background: var(--surf);
  border-bottom: 1px solid var(--bord);
  flex-shrink: 0;
}

.page-title { font-family:"Playfair Display",serif; font-size:1.1rem; font-weight:600; color:var(--txt); }
.page-sub { font-size:.72rem; color:var(--txt-3); margin-top:2px; }

.btn-ghost {
  display: flex;
  align-items: center;
  gap: 6px;
  background: none;
  border: 1px solid var(--bord);
  color: var(--txt-2);
  font-size: .78rem;
  padding: 6px 12px;
  border-radius: 8px;
  cursor: pointer;
  font-family: 'DM Sans', sans-serif;
  transition: .15s;
  &:hover { background: var(--surf-2); color: var(--txt); }
}

/* Templates grid */
.templates-grid {
  padding: 24px;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 12px;
  overflow-y: auto;
}

.template-card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 16px 18px;
  background: var(--surf);
  border: 1px solid var(--bord);
  border-radius: 12px;
  cursor: pointer;
  text-align: left;
  transition: .15s;
  font-family: 'DM Sans', sans-serif;

  &:hover { border-color: var(--prim-3); box-shadow: var(--shadow-md); transform: translateY(-1px); }
}

.tmpl-icon { font-size: 1.6rem; flex-shrink: 0; }
.tmpl-info { flex: 1; }
.tmpl-name { font-size: .88rem; font-weight: 500; color: var(--txt); margin-bottom: 2px; }
.tmpl-desc { font-size: .75rem; color: var(--txt-3); }
.tmpl-arrow { color: var(--txt-3); flex-shrink: 0; }

/* Form */
.form-container { padding: 24px; overflow-y: auto; max-width: 680px; width: 100%; margin: 0 auto; }

.form-header {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--bord);
}

.form-icon { font-size: 2rem; }
.form-title { font-family:"Playfair Display",serif; font-size:1.1rem; font-weight:600; color:var(--txt); }
.form-sub { font-size:.75rem; color:var(--txt-3); margin-top:2px; }

.form-fields { display: flex; flex-direction: column; gap: 16px; }

.field-group { display: flex; flex-direction: column; gap: 6px; }
.field-label { font-size: .8rem; font-weight: 500; color: var(--txt-2); }
.required { color: var(--red); margin-left: 2px; }

.field-input {
  border: 1px solid var(--bord);
  border-radius: 8px;
  padding: 9px 12px;
  font-size: .85rem;
  font-family: 'DM Sans', sans-serif;
  color: var(--txt);
  background: var(--surf);
  transition: border-color .2s;
  outline: none;

  &:focus { border-color: var(--prim-3); }
  &::placeholder { color: var(--txt-3); }
}

.field-textarea { resize: vertical; min-height: 80px; }
.field-select { cursor: pointer; }

.form-actions { margin-top: 24px; padding-top: 16px; border-top: 1px solid var(--bord); }

.btn-primary {
  display: flex;
  align-items: center;
  gap: 8px;
  background: var(--prim);
  color: white;
  border: none;
  border-radius: 10px;
  padding: 12px 24px;
  font-size: .88rem;
  font-family: 'DM Sans', sans-serif;
  cursor: pointer;
  transition: .15s;

  &:hover:not(:disabled) { background: var(--prim-2); }
  &:disabled { opacity: .5; cursor: not-allowed; }
}

.btn-spinner {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255,255,255,.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin .7s linear infinite;
}

@keyframes spin { to { transform: rotate(360deg); } }

/* Preview */
.preview-container { display:flex; flex-direction:column; flex:1; overflow:hidden; }

.preview-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 24px;
  background: var(--surf);
  border-bottom: 1px solid var(--bord);
  flex-shrink: 0;
}

.download-btns { display: flex; gap: 8px; }

.btn-download {
  display: flex;
  align-items: center;
  gap: 6px;
  border: 1px solid var(--bord);
  border-radius: 8px;
  padding: 7px 14px;
  font-size: .78rem;
  font-family: 'DM Sans', sans-serif;
  cursor: pointer;
  transition: .15s;

  &.word { background: #1a5296; color: white; border-color: #1a5296; &:hover { background: #0f3a72; } }
  &.pdf  { background: #c0392b; color: white; border-color: #c0392b; &:hover { background: #962d22; } }
}

.preview-doc { flex:1; overflow-y:auto; padding:32px; }

.generating-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 300px;
  gap: 16px;
}

.gen-spinner {
  width: 40px;
  height: 40px;
  border: 3px solid var(--bord);
  border-top-color: var(--prim);
  border-radius: 50%;
  animation: spin .8s linear infinite;
}

.gen-sub { font-size: .8rem; color: var(--txt-3); }

.doc-content {
  max-width: 700px;
  margin: 0 auto;
  font-family: 'DM Sans', sans-serif;
  font-size: .9rem;
  line-height: 1.7;
  color: var(--txt);
  background: var(--surf);
  padding: 40px 48px;
  border: 1px solid var(--bord);
  border-radius: 8px;
  box-shadow: var(--shadow);

  ::ng-deep {
    h3 { font-family:'Playfair Display',serif; font-size:1rem; font-weight:600; color:var(--prim); margin:18px 0 8px; border-bottom:1px solid var(--bord); padding-bottom:5px; }
    h4 { font-size:.88rem; font-weight:500; color:var(--prim-2); margin:12px 0 5px; }
    strong { color:var(--prim); font-weight:500; }
    code { font-family:'DM Mono',monospace; font-size:.8em; background:var(--surf-2); padding:1px 5px; border-radius:3px; }
    ul { padding-left:20px; margin:6px 0; }
    li { margin:3px 0; }
    p { margin:6px 0; }
  }
}
'@)
OK "Documents component (generador completo)"

# ══════════════════════════════════════════════════════
# 7. ACTUALIZAR RUTAS
# ══════════════════════════════════════════════════════
PASO "Actualizando rutas"

[System.IO.File]::WriteAllText("$fe\app.routes.ts", @'
import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: '/chat', pathMatch: 'full' },
  {
    path: 'chat',
    loadComponent: () => import('./features/chat/chat.component').then(m => m.ChatComponent)
  },
  {
    path: 'documents',
    loadComponent: () => import('./features/documents/documents.component').then(m => m.DocumentsComponent)
  },
  {
    path: 'cases',
    loadComponent: () => import('./features/cases/cases.component').then(m => m.CasesComponent)
  },
  {
    path: 'library',
    loadComponent: () => import('./features/library/library.component').then(m => m.LibraryComponent)
  },
  {
    path: 'settings',
    loadComponent: () => import('./features/settings/settings.component').then(m => m.SettingsComponent)
  },
  {
    path: 'auth/callback',
    loadComponent: () => import('./core/auth-callback/auth-callback.component').then(m => m.AuthCallbackComponent)
  },
  { path: '**', redirectTo: '/chat' }
];
'@)
OK "app.routes.ts"

# ══════════════════════════════════════════════════════
# RESUMEN
# ══════════════════════════════════════════════════════
Write-Host @"

===============================================================
  JURIS-FREE Bolivia v2 — Rediseno y generador listos
===============================================================

  NUEVO:
  - Sidebar de navegacion profesional (azul oscuro + dorado)
  - Chat rediseñado con markdown, acciones rapidas, exportar
  - Generador de 6 documentos legales bolivianos:
    * Demanda Civil (Ley 439)
    * Contrato de Compraventa (Cod. Civil)
    * Poder Notarial
    * Memorial Judicial
    * Contrato de Trabajo (LGT)
    * Denuncia Penal (Ley 1970 + Ley 1768)
  - Export a Word (.docx) con cabeceras y pies de pagina
  - Export a PDF via impresion del navegador

  Angular recarga automaticamente.
  Abrir: http://localhost:4200

===============================================================
"@ -ForegroundColor Green
