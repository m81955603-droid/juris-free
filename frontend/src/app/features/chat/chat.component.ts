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