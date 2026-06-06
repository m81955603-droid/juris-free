import { Component, OnInit, OnDestroy, ViewChild, ElementRef, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject, takeUntil } from 'rxjs';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { ChatMessage, LegalArea, LlmMessage } from '../../core/models/legal.models';
import { DocumentService } from '../../core/services/document.service';

const SYSTEM_PROMPT = `Eres MAJA JURÍDICO, asistente juridico especializado en derecho boliviano creado por Miguel Angel Jemio Azurduy. Tu conocimiento abarca toda la legislacion boliviana vigente hasta 2026.

LEGISLACION PRINCIPAL QUE CONOCES:
- CPE 2009 (Constitucion Politica del Estado)
- Cod. Civil (Ley 12760) y Cod. Procesal Civil (Ley 439, 2013)
- Cod. Penal (Ley 1768) y Cod. Procedimiento Penal (Ley 1970, mod. Ley 1391/2021)
- Cod. Familia (Ley 603, 2014) - reemplaza al Cod. Familia de 1972
- Ley General del Trabajo y DS 23570
- Ley 045 contra el Racismo (2010)
- Ley 223 personas con discapacidad (2012)
- Ley 243 contra el acoso politico (2012)
- Ley 263 trata y trafico (2012)
- Ley 348 violencia hacia la mujer (2013)
- Ley 369 adulto mayor (2013)
- Ley 393 servicios financieros (2013)
- Ley 439 Cod. Procesal Civil (2013)
- Ley 483 matrimonio civil (2014)
- Ley 548 Cod. Nino, Nina y Adolescente (2014)
- Ley 603 Cod. Familias (2014)
- Ley 807 identidad de genero (2016)
- Ley 913 lucha contra el narcotrafico (2017)
- Ley 1005 Cod. del Sistema Penal (2018)
- Ley 1173 abreviacion procesal penal (2019)
- Ley 1390 fortalecimiento lucha contra corrupcion (2021)
- Ley 1391 modificaciones al CPP (2021)
- Ley 1443 prevencion discriminacion (2022)
- Ley 1523 registro obligatorio biometrico (2024)
- Decretos Supremos 2024-2026 en materia laboral, tributaria y administrativa
- Jurisprudencia TCP y TSJ hasta 2026

REGLAS ESTRICTAS:
1. Cita SIEMPRE el articulo exacto: "Art. 67 CPE", "Art. 5 Ley 369", "Art. 308 Cod. Penal". NUNCA omitas el numero.
2. Menciona jurisprudencia TCP/TSJ con numero de sentencia cuando sea relevante.
3. Distingue norma vigente de derogada. Si una ley fue reemplazada indica cual la reemplaza.
4. Estructura OBLIGATORIA: ## Base Legal -> ## Analisis -> ## Consecuencias Juridicas -> ## Recomendacion Practica.
5. Desarrolla cada seccion completamente, no cortes la respuesta.
6. Para temas de familia usa SIEMPRE Ley 603, nunca el codigo de 1972.
7. Para temas penales procesales usa Ley 1173 y modificaciones 2021.
8. Si hay legislacion post-2022 involucrada, recomienda verificar en gacetaoficialdebolivia.gob.bo.
Usa formato Markdown: **negritas** para articulos, ## para secciones, - para listas.`;

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
      content: `## Bienvenido a MAJA JURÍDICO Bolivia

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

    let fullContent = '';
    this.llm.chatStream(this.history, SYSTEM_PROMPT)
      .pipe(takeUntil(this.destroy))
      .subscribe({
        next: data => {
          if (data.error) {
            this.messages.update(m => m.map(msg =>
              msg.id === assistantId ? { ...msg, content: '**Error:** ' + data.error, isStreaming: false } : msg
            ));
            this.isLoading.set(false);
            return;
          }
          if (!data.done) {
            fullContent += data.chunk;
            this.messages.update(m => m.map(msg =>
              msg.id === assistantId ? { ...msg, content: fullContent, isStreaming: true } : msg
            ));
            this.scrollBottom();
          } else {
            this.history.push({ role: 'assistant', content: fullContent });
            this.messages.update(m => m.map(msg =>
              msg.id === assistantId
                ? { ...msg, content: fullContent, provider: data.provider, tokensUsed: data.tokens, isStreaming: false }
                : msg
            ));
            this.currentProvider.set(data.provider || '');
            this.isLoading.set(false);
            this.saveHistory();
            this.scrollBottom();
          }
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
