# JURIS-FREE Bolivia — Analisis de Documentos con IA
# Sube PDF o Word y la IA lo analiza, resume y responde preguntas
# PowerShell 7+

param([string]$Ruta = "C:\proyectos\juris-free")

$fe = "$Ruta\frontend\src\app"
$ErrorActionPreference = "Continue"

function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }

Write-Host "`n  JURIS-FREE — Analisis de Documentos con IA`n" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════
# 1. DEPENDENCIAS
# ══════════════════════════════════════════════════════
PASO "Instalando dependencias"
Set-Location "$Ruta\frontend"
npm install pdfjs-dist mammoth --save --silent 2>&1 | Out-Null
OK "pdfjs-dist + mammoth instalados"

# ══════════════════════════════════════════════════════
# 2. COMPONENTE ANALISIS DE DOCUMENTOS
# ══════════════════════════════════════════════════════
PASO "Componente Analisis de Documentos"
New-Item -ItemType Directory -Path "$fe\features\analyzer" -Force | Out-Null

[System.IO.File]::WriteAllText("$fe\features\analyzer\analyzer.component.ts", @'
import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { DocumentService } from '../../core/services/document.service';

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
}

interface AnalysisResult {
  tipo:       string;
  resumen:    string;
  partes:     string[];
  fechas:     string[];
  montos:     string[];
  articulos:  string[];
  riesgos:    string[];
  siguiente:  string;
}

@Component({
  selector:    'app-analyzer',
  standalone:  true,
  imports:     [CommonModule, FormsModule],
  templateUrl: './analyzer.component.html',
  styleUrls:   ['./analyzer.component.scss']
})
export class AnalyzerComponent {
  private llm    = inject(LlmProxyService);
  private docSvc = inject(DocumentService);

  // Estado
  step            = signal<'upload' | 'analyzing' | 'ready'>('upload');
  dragOver        = signal(false);
  isAnalyzing     = signal(false);
  isAnswering     = signal(false);
  fileName        = signal('');
  fileSize        = signal(0);
  fileType        = signal('');
  extractedText   = signal('');
  analysis        = signal<AnalysisResult | null>(null);
  chatMessages    = signal<ChatMessage[]>([]);
  question        = '';
  activeTab       = signal<'resumen' | 'chat' | 'export'>('resumen');

  // Preguntas sugeridas segun tipo de documento
  readonly preguntasSugeridas: Record<string, string[]> = {
    'contrato': [
      '¿Cuáles son las obligaciones principales de cada parte?',
      '¿Cuáles son las causales de resolución del contrato?',
      '¿Hay clausulas abusivas o riesgosas?',
      '¿Cuál es el plazo de vigencia?'
    ],
    'demanda': [
      '¿Cuál es el petitorio principal?',
      '¿Qué pruebas se ofrecen?',
      '¿Están correctamente citados los articulos bolivianos?',
      '¿Cuáles son los plazos procesales aplicables?'
    ],
    'sentencia': [
      '¿Cuál es el fallo principal?',
      '¿Qué argumentos usó el juez?',
      '¿Es apelable esta sentencia?',
      '¿Cuáles son los efectos juridicos?'
    ],
    'default': [
      '¿Cuáles son los puntos más importantes?',
      '¿Hay algún riesgo legal en este documento?',
      '¿Qué normativa boliviana aplica?',
      '¿Qué pasos debo seguir después?'
    ]
  };

  // ── CARGA DE ARCHIVOS ─────────────────────────────

  onDragOver(e: DragEvent): void { e.preventDefault(); this.dragOver.set(true); }
  onDragLeave(): void { this.dragOver.set(false); }

  onDrop(e: DragEvent): void {
    e.preventDefault();
    this.dragOver.set(false);
    const files = e.dataTransfer?.files;
    if (files?.length) this.processFile(files[0]);
  }

  onFileSelected(e: Event): void {
    const input = e.target as HTMLInputElement;
    if (input.files?.length) this.processFile(input.files[0]);
  }

  async processFile(file: File): Promise<void> {
    const validTypes = ['.pdf', '.docx', '.doc', '.txt'];
    const ext = '.' + file.name.split('.').pop()?.toLowerCase();

    if (!validTypes.includes(ext)) {
      alert('Formato no soportado. Usa PDF, Word (.docx) o texto (.txt)');
      return;
    }

    if (file.size > 20 * 1024 * 1024) {
      alert('Archivo muy grande. Máximo 20MB.');
      return;
    }

    this.fileName.set(file.name);
    this.fileSize.set(file.size);
    this.fileType.set(ext);
    this.step.set('analyzing');
    this.isAnalyzing.set(true);

    try {
      let texto = '';

      if (ext === '.pdf') {
        texto = await this.extractFromPdf(file);
      } else if (ext === '.docx' || ext === '.doc') {
        texto = await this.extractFromDocx(file);
      } else if (ext === '.txt') {
        texto = await file.text();
      }

      if (!texto.trim()) {
        alert('No se pudo extraer texto del documento. Puede ser un PDF escaneado (imagen).');
        this.step.set('upload');
        this.isAnalyzing.set(false);
        return;
      }

      this.extractedText.set(texto);

      // Analizar con IA
      await this.analyzeDocument(texto, file.name);

    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Error desconocido';
      alert('Error procesando el archivo: ' + msg);
      this.step.set('upload');
      this.isAnalyzing.set(false);
    }
  }

  private async extractFromPdf(file: File): Promise<string> {
    try {
      // Usar pdf.js para extraer texto
      const pdfjsLib = await import('pdfjs-dist');
      pdfjsLib.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.js`;

      const arrayBuffer = await file.arrayBuffer();
      const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;

      let fullText = '';
      const maxPages = Math.min(pdf.numPages, 50); // Max 50 paginas

      for (let i = 1; i <= maxPages; i++) {
        const page    = await pdf.getPage(i);
        const content = await page.getTextContent();
        const pageText = content.items
          .map((item: any) => item.str)
          .join(' ');
        fullText += pageText + '\n\n';
      }

      return fullText.trim();
    } catch (err) {
      throw new Error('Error leyendo PDF: ' + (err as Error).message);
    }
  }

  private async extractFromDocx(file: File): Promise<string> {
    const mammoth    = await import('mammoth');
    const arrayBuffer = await file.arrayBuffer();
    const result     = await mammoth.extractRawText({ arrayBuffer });
    return result.value || '';
  }

  private async analyzeDocument(texto: string, nombre: string): Promise<void> {
    const textoCorto = texto.substring(0, 12000);

    const prompt = `Analiza este documento legal boliviano y responde SOLO en JSON valido con esta estructura exacta:

{
  "tipo": "tipo de documento (contrato/demanda/sentencia/poder/memorial/ley/otro)",
  "resumen": "resumen ejecutivo en 3-4 oraciones claras",
  "partes": ["lista de partes o personas mencionadas"],
  "fechas": ["fechas importantes encontradas"],
  "montos": ["montos o valores economicos encontrados"],
  "articulos": ["articulos legales bolivianos citados"],
  "riesgos": ["riesgos o puntos criticos identificados (maximo 4)"],
  "siguiente": "recomendacion de que hacer a continuacion"
}

DOCUMENTO: "${nombre}"

CONTENIDO:
${textoCorto}

Responde SOLO el JSON, sin texto adicional, sin markdown.`;

    return new Promise((resolve) => {
      this.llm.chat([{ role: 'user', content: prompt }]).subscribe({
        next: resp => {
          try {
            // Limpiar respuesta
            let json = resp.content.trim();
            json = json.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

            const result = JSON.parse(json) as AnalysisResult;
            this.analysis.set(result);

            // Mensaje inicial del chat
            this.chatMessages.set([{
              role:      'assistant',
              content:   `He analizado **${nombre}** exitosamente.\n\n**Tipo:** ${result.tipo}\n\n**Resumen:** ${result.resumen}\n\nPuedes hacerme cualquier pregunta sobre el documento.`,
              timestamp: new Date()
            }]);

          } catch {
            // Si falla el JSON, crear analisis basico
            this.analysis.set({
              tipo:      'documento legal',
              resumen:   resp.content.substring(0, 400),
              partes:    [],
              fechas:    [],
              montos:    [],
              articulos: [],
              riesgos:   [],
              siguiente: 'Revisa el documento manualmente para mas detalles.'
            });
            this.chatMessages.set([{
              role:      'assistant',
              content:   'He procesado el documento. Puedes hacerme preguntas sobre su contenido.',
              timestamp: new Date()
            }]);
          }

          this.isAnalyzing.set(false);
          this.step.set('ready');
          resolve();
        },
        error: () => {
          this.isAnalyzing.set(false);
          this.step.set('upload');
          resolve();
        }
      });
    });
  }

  // ── CHAT SOBRE EL DOCUMENTO ───────────────────────

  askQuestion(q?: string): void {
    const pregunta = (q || this.question).trim();
    if (!pregunta || this.isAnswering()) return;

    this.question = '';
    this.activeTab.set('chat');
    this.isAnswering.set(true);

    const userMsg: ChatMessage = { role: 'user', content: pregunta, timestamp: new Date() };
    this.chatMessages.update(msgs => [...msgs, userMsg]);

    const texto = this.extractedText();
    const contexto = texto.substring(0, 10000);

    const prompt = `Eres un abogado boliviano experto. Analiza el siguiente documento y responde la pregunta del usuario.

DOCUMENTO:
${contexto}

PREGUNTA: ${pregunta}

Responde de forma clara, citando partes especificas del documento cuando sea relevante. Si la pregunta involucra normativa boliviana, cita los articulos correspondientes.`;

    this.llm.chat([{ role: 'user', content: prompt }]).subscribe({
      next: resp => {
        const assistantMsg: ChatMessage = {
          role:      'assistant',
          content:   resp.content,
          timestamp: new Date()
        };
        this.chatMessages.update(msgs => [...msgs, assistantMsg]);
        this.isAnswering.set(false);
      },
      error: err => {
        this.chatMessages.update(msgs => [...msgs, {
          role:      'assistant',
          content:   'Error: ' + err.message,
          timestamp: new Date()
        }]);
        this.isAnswering.set(false);
      }
    });
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.askQuestion();
    }
  }

  // ── EXPORT ────────────────────────────────────────

  async exportAnalysis(): Promise<void> {
    const a = this.analysis();
    if (!a) return;

    const content = `## Analisis del Documento: ${this.fileName()}

**Tipo:** ${a.tipo}

## Resumen
${a.resumen}

## Partes Involucradas
${a.partes.map(p => `- ${p}`).join('\n') || '- No identificadas'}

## Fechas Importantes
${a.fechas.map(f => `- ${f}`).join('\n') || '- No identificadas'}

## Montos y Valores
${a.montos.map(m => `- ${m}`).join('\n') || '- No identificados'}

## Articulos Legales Citados
${a.articulos.map(art => `- ${art}`).join('\n') || '- No identificados'}

## Puntos de Riesgo
${a.riesgos.map(r => `- ${r}`).join('\n') || '- No identificados'}

## Recomendacion
${a.siguiente}

---
*Analisis generado por JURIS-FREE Bolivia*`;

    await this.docSvc.generateLegalDocument({
      titulo:   'Analisis — ' + this.fileName(),
      contenido: content
    });
  }

  async exportChat(): Promise<void> {
    const msgs = this.chatMessages();
    const content = msgs
      .map(m => `**${m.role === 'user' ? 'Pregunta' : 'Respuesta'}:**\n${m.content}`)
      .join('\n\n---\n\n');

    await this.docSvc.generateLegalDocument({
      titulo:   'Consultas — ' + this.fileName(),
      contenido: content
    });
  }

  // ── HELPERS ───────────────────────────────────────

  resetUpload(): void {
    this.step.set('upload');
    this.fileName.set('');
    this.extractedText.set('');
    this.analysis.set(null);
    this.chatMessages.set([]);
    this.question = '';
  }

  getSugeridas(): string[] {
    const tipo = this.analysis()?.tipo?.toLowerCase() || '';
    if (tipo.includes('contrato')) return this.preguntasSugeridas['contrato'];
    if (tipo.includes('demanda'))  return this.preguntasSugeridas['demanda'];
    if (tipo.includes('sentencia')) return this.preguntasSugeridas['sentencia'];
    return this.preguntasSugeridas['default'];
  }

  formatSize(bytes: number): string {
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
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
}
'@)
OK "analyzer.component.ts"

[System.IO.File]::WriteAllText("$fe\features\analyzer\analyzer.component.html", @'
<div class="analyzer-layout">

  <header class="page-header">
    <div>
      <h1 class="page-title">Análisis de Documentos</h1>
      <p class="page-sub">Sube PDF o Word — la IA analiza, resume y responde tus preguntas</p>
    </div>
    @if (step() === 'ready') {
      <button class="btn-ghost" (click)="resetUpload()">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"/>
        </svg>
        Analizar otro
      </button>
    }
  </header>

  <div class="main-content">

    <!-- UPLOAD -->
    @if (step() === 'upload') {
      <div class="upload-view">
        <div class="drop-zone"
             [class.drag-over]="dragOver()"
             (dragover)="onDragOver($event)"
             (dragleave)="onDragLeave()"
             (drop)="onDrop($event)"
             (click)="fileInput.click()">
          <input #fileInput type="file" accept=".pdf,.docx,.doc,.txt" style="display:none" (change)="onFileSelected($event)">
          <div class="drop-content">
            <div class="drop-icons">
              <span class="file-icon pdf">PDF</span>
              <span class="file-icon word">DOC</span>
              <span class="file-icon txt">TXT</span>
            </div>
            <h3>Arrastra tu documento aquí</h3>
            <p>o haz clic para seleccionar</p>
            <p class="drop-hint">PDF · Word (.docx) · Texto (.txt) · Máximo 20MB</p>
          </div>
        </div>

        <div class="upload-features">
          <h4>¿Qué puede analizar la IA?</h4>
          <div class="features-grid">
            <div class="feature-item">
              <span class="feat-icon">📋</span>
              <div>
                <p class="feat-title">Contratos</p>
                <p class="feat-desc">Obligaciones, riesgos, clausulas abusivas, plazos</p>
              </div>
            </div>
            <div class="feature-item">
              <span class="feat-icon">⚖</span>
              <div>
                <p class="feat-title">Demandas y Memoriales</p>
                <p class="feat-desc">Petitorio, fundamentos, articulos citados, plazos</p>
              </div>
            </div>
            <div class="feature-item">
              <span class="feat-icon">🏛</span>
              <div>
                <p class="feat-title">Sentencias</p>
                <p class="feat-desc">Fallo, argumentos, apelabilidad, efectos juridicos</p>
              </div>
            </div>
            <div class="feature-item">
              <span class="feat-icon">📜</span>
              <div>
                <p class="feat-title">Poderes y Escrituras</p>
                <p class="feat-desc">Facultades, vigencia, limitaciones, validez</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    }

    <!-- ANALIZANDO -->
    @if (step() === 'analyzing') {
      <div class="analyzing-view">
        <div class="file-card">
          <span class="file-card-icon">{{ fileType() === '.pdf' ? '📕' : '📘' }}</span>
          <div>
            <p class="file-card-name">{{ fileName() }}</p>
            <p class="file-card-size">{{ formatSize(fileSize()) }}</p>
          </div>
        </div>
        <div class="progress-steps">
          <div class="prog-step done">
            <span class="prog-dot"></span>
            <span>Archivo cargado</span>
          </div>
          <div class="prog-step active">
            <span class="prog-dot spinning"></span>
            <span>Extrayendo texto...</span>
          </div>
          <div class="prog-step">
            <span class="prog-dot"></span>
            <span>Analizando con IA...</span>
          </div>
          <div class="prog-step">
            <span class="prog-dot"></span>
            <span>Preparando resumen</span>
          </div>
        </div>
        <p class="analyzing-hint">Esto puede tomar 10-20 segundos según el tamaño del documento</p>
      </div>
    }

    <!-- RESULTADO -->
    @if (step() === 'ready') {
      <div class="result-view">

        <!-- Info del archivo -->
        <div class="file-info-bar">
          <span class="file-badge">{{ fileType() === '.pdf' ? '📕 PDF' : '📘 Word' }}</span>
          <span class="file-name">{{ fileName() }}</span>
          <span class="file-size">{{ formatSize(fileSize()) }}</span>
          @if (analysis()) {
            <span class="doc-type-badge">{{ analysis()!.tipo }}</span>
          }
        </div>

        <!-- Tabs -->
        <div class="tabs">
          <button class="tab" [class.active]="activeTab() === 'resumen'" (click)="activeTab.set('resumen')">
            Resumen y analisis
          </button>
          <button class="tab" [class.active]="activeTab() === 'chat'" (click)="activeTab.set('chat')">
            Preguntas ({{ chatMessages().length - 1 }})
          </button>
          <button class="tab" [class.active]="activeTab() === 'export'" (click)="activeTab.set('export')">
            Exportar
          </button>
        </div>

        <!-- Tab Resumen -->
        @if (activeTab() === 'resumen' && analysis()) {
          @let a = analysis()!;
          <div class="resumen-view">

            <div class="resumen-card main">
              <h3>Resumen ejecutivo</h3>
              <p>{{ a.resumen }}</p>
            </div>

            <div class="resumen-grid">
              @if (a.partes.length > 0) {
                <div class="resumen-card">
                  <h4>Partes</h4>
                  <ul>@for (p of a.partes; track p) { <li>{{ p }}</li> }</ul>
                </div>
              }
              @if (a.fechas.length > 0) {
                <div class="resumen-card">
                  <h4>Fechas importantes</h4>
                  <ul>@for (f of a.fechas; track f) { <li>{{ f }}</li> }</ul>
                </div>
              }
              @if (a.montos.length > 0) {
                <div class="resumen-card">
                  <h4>Montos y valores</h4>
                  <ul>@for (m of a.montos; track m) { <li>{{ m }}</li> }</ul>
                </div>
              }
              @if (a.articulos.length > 0) {
                <div class="resumen-card">
                  <h4>Articulos bolivianos citados</h4>
                  <ul>@for (art of a.articulos; track art) { <li>{{ art }}</li> }</ul>
                </div>
              }
            </div>

            @if (a.riesgos.length > 0) {
              <div class="resumen-card riesgos">
                <h4>Puntos de atención</h4>
                <ul>@for (r of a.riesgos; track r) { <li>{{ r }}</li> }</ul>
              </div>
            }

            @if (a.siguiente) {
              <div class="resumen-card siguiente">
                <h4>Recomendación</h4>
                <p>{{ a.siguiente }}</p>
              </div>
            }

            <!-- Preguntas sugeridas -->
            <div class="sugeridas">
              <p class="sugeridas-title">Preguntas frecuentes sobre este tipo de documento:</p>
              <div class="sugeridas-grid">
                @for (q of getSugeridas(); track q) {
                  <button class="sugerida-btn" (click)="askQuestion(q)">
                    {{ q }}
                  </button>
                }
              </div>
            </div>
          </div>
        }

        <!-- Tab Chat -->
        @if (activeTab() === 'chat') {
          <div class="chat-view">
            <div class="chat-messages">
              @for (msg of chatMessages(); track msg.timestamp) {
                <div class="chat-msg" [class.user]="msg.role === 'user'" [class.assistant]="msg.role === 'assistant'">
                  <div class="chat-bubble">
                    <div class="chat-content" [innerHTML]="renderMarkdown(msg.content)"></div>
                    <span class="chat-time">{{ msg.timestamp | date:'HH:mm' }}</span>
                  </div>
                </div>
              }
              @if (isAnswering()) {
                <div class="chat-msg assistant">
                  <div class="chat-bubble">
                    <div class="typing"><span></span><span></span><span></span></div>
                  </div>
                </div>
              }
            </div>

            <div class="chat-input-area">
              <div class="sugeridas-chips">
                @for (q of getSugeridas(); track q) {
                  <button class="chip" (click)="askQuestion(q)">{{ q }}</button>
                }
              </div>
              <div class="input-row">
                <textarea
                  class="chat-input"
                  [(ngModel)]="question"
                  placeholder="Pregunta sobre el documento..."
                  rows="2"
                  [disabled]="isAnswering()"
                  (keydown)="onKeydown($event)">
                </textarea>
                <button class="send-btn" (click)="askQuestion()" [disabled]="isAnswering() || !question.trim()">
                  @if (isAnswering()) {
                    <div class="send-spinner"></div>
                  } @else {
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 19V5m0 0l-7 7m7-7l7 7"/>
                    </svg>
                  }
                </button>
              </div>
            </div>
          </div>
        }

        <!-- Tab Export -->
        @if (activeTab() === 'export') {
          <div class="export-view">
            <div class="export-card" (click)="exportAnalysis()">
              <span class="export-icon">📊</span>
              <div>
                <h3>Exportar análisis completo</h3>
                <p>Descarga el resumen, partes, fechas, riesgos y recomendaciones en Word</p>
              </div>
              <span class="export-arrow">→</span>
            </div>
            <div class="export-card" (click)="exportChat()">
              <span class="export-icon">💬</span>
              <div>
                <h3>Exportar preguntas y respuestas</h3>
                <p>Descarga todas las consultas realizadas sobre el documento en Word</p>
              </div>
              <span class="export-arrow">→</span>
            </div>
          </div>
        }

      </div>
    }

  </div>
</div>
'@)

[System.IO.File]::WriteAllText("$fe\features\analyzer\analyzer.component.scss", @'
:host { display:flex; flex-direction:column; height:100vh; overflow:hidden; }
.analyzer-layout { display:flex; flex-direction:column; height:100vh; overflow:hidden; background:var(--bg); }

.page-header {
  display:flex; align-items:center; justify-content:space-between;
  padding:16px 24px; background:var(--surf); border-bottom:1px solid var(--bord); flex-shrink:0;
}
.page-title { font-family:"Playfair Display",serif; font-size:1.1rem; font-weight:600; color:var(--txt); }
.page-sub { font-size:.72rem; color:var(--txt-3); margin-top:2px; }

.btn-ghost {
  display:flex; align-items:center; gap:6px; background:none; border:1px solid var(--bord);
  color:var(--txt-2); font-size:.78rem; padding:6px 12px; border-radius:8px; cursor:pointer;
  font-family:'DM Sans',sans-serif; transition:.15s;
  &:hover { background:var(--surf-2); color:var(--txt); }
}

.main-content { flex:1; overflow-y:auto; }

/* Upload */
.upload-view { padding:24px; max-width:700px; margin:0 auto; }

.drop-zone {
  border:2px dashed var(--bord-2); border-radius:16px; padding:48px 24px;
  text-align:center; cursor:pointer; transition:.2s; background:var(--surf); margin-bottom:24px;
  &:hover, &.drag-over { border-color:var(--gold); background:var(--gold-bg); }
}
.drop-content { display:flex; flex-direction:column; align-items:center; gap:12px; }
.drop-icons { display:flex; gap:8px; margin-bottom:4px; }
.file-icon {
  padding:5px 10px; border-radius:6px; font-size:.72rem; font-weight:700; letter-spacing:.04em;
  &.pdf  { background:#ffecec; color:#c0392b; }
  &.word { background:#eaf0ff; color:#1a5296; }
  &.txt  { background:#f4f2ee; color:#7a7268; }
}
.drop-zone h3 { font-family:"Playfair Display",serif; font-size:1rem; color:var(--txt); }
.drop-zone p  { font-size:.82rem; color:var(--txt-3); }
.drop-hint    { background:var(--surf-2); padding:4px 14px; border-radius:20px; font-size:.72rem !important; }

.upload-features { background:var(--surf); border:1px solid var(--bord); border-radius:12px; padding:18px 20px;
  h4 { font-size:.82rem; font-weight:500; color:var(--txt-2); margin-bottom:12px; }
}
.features-grid { display:grid; grid-template-columns:1fr 1fr; gap:10px; }
.feature-item { display:flex; gap:10px; align-items:flex-start; }
.feat-icon { font-size:1.2rem; flex-shrink:0; }
.feat-title { font-size:.82rem; font-weight:500; color:var(--txt); margin-bottom:2px; }
.feat-desc  { font-size:.72rem; color:var(--txt-3); line-height:1.4; }

/* Analyzing */
.analyzing-view {
  display:flex; flex-direction:column; align-items:center; justify-content:center;
  gap:24px; padding:48px; height:100%;
}
.file-card {
  display:flex; align-items:center; gap:12px; background:var(--surf); border:1px solid var(--bord);
  border-radius:12px; padding:14px 20px;
  .file-card-icon { font-size:2rem; }
  .file-card-name { font-size:.88rem; font-weight:500; color:var(--txt); }
  .file-card-size { font-size:.72rem; color:var(--txt-3); }
}
.progress-steps { display:flex; flex-direction:column; gap:10px; min-width:280px; }
.prog-step {
  display:flex; align-items:center; gap:10px; font-size:.82rem; color:var(--txt-3);
  &.done   .prog-dot { background:var(--green); }
  &.active .prog-dot { background:var(--prim); }
  &.active { color:var(--txt); font-weight:500; }
}
.prog-dot {
  width:10px; height:10px; border-radius:50%; background:var(--bord); flex-shrink:0;
  &.spinning { animation:spin .8s linear infinite; border:2px solid var(--prim); border-top-color:transparent; background:transparent; width:12px; height:12px; }
}
@keyframes spin { to { transform:rotate(360deg); } }
.analyzing-hint { font-size:.75rem; color:var(--txt-3); text-align:center; }

/* Result */
.result-view { display:flex; flex-direction:column; height:100%; }

.file-info-bar {
  display:flex; align-items:center; gap:10px; padding:10px 24px;
  background:var(--surf); border-bottom:1px solid var(--bord); flex-shrink:0; flex-wrap:wrap;
}
.file-badge   { background:var(--surf-2); border:1px solid var(--bord); font-size:.72rem; padding:3px 8px; border-radius:6px; color:var(--txt-2); }
.file-name    { font-size:.82rem; font-weight:500; color:var(--txt); flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.file-size    { font-size:.72rem; color:var(--txt-3); font-family:'DM Mono',monospace; }
.doc-type-badge { background:var(--gold-bg); border:1px solid rgba(184,135,42,.2); color:var(--gold); font-size:.72rem; padding:3px 10px; border-radius:20px; font-weight:500; text-transform:capitalize; }

/* Tabs */
.tabs { display:flex; gap:0; padding:0 24px; background:var(--surf); border-bottom:1px solid var(--bord); flex-shrink:0; }
.tab {
  padding:10px 18px; border:none; background:none; font-size:.82rem; font-family:'DM Sans',sans-serif;
  color:var(--txt-3); cursor:pointer; border-bottom:2px solid transparent; transition:.15s; margin-bottom:-1px;
  &:hover  { color:var(--txt-2); }
  &.active { color:var(--prim); border-bottom-color:var(--prim); font-weight:500; }
}

/* Resumen */
.resumen-view { padding:20px 24px; overflow-y:auto; display:flex; flex-direction:column; gap:12px; }
.resumen-card {
  background:var(--surf); border:1px solid var(--bord); border-radius:10px; padding:14px 18px;
  h3 { font-family:"Playfair Display",serif; font-size:.92rem; font-weight:600; color:var(--prim); margin-bottom:8px; }
  h4 { font-size:.78rem; font-weight:500; color:var(--txt-2); margin-bottom:6px; text-transform:uppercase; letter-spacing:.04em; }
  p  { font-size:.84rem; color:var(--txt-2); line-height:1.6; }
  ul { padding-left:16px; }
  li { font-size:.82rem; color:var(--txt-2); margin:3px 0; }
  &.main    { border-color:rgba(26,58,92,.15); background:rgba(26,58,92,.03); }
  &.riesgos { border-color:rgba(192,57,43,.2); background:rgba(192,57,43,.03); h4 { color:#c0392b; } li { color:#8b2820; } }
  &.siguiente { border-color:rgba(26,107,60,.2); background:rgba(26,107,60,.03); h4 { color:#1a6b3c; } p { color:#1a4a2a; } }
}
.resumen-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(220px, 1fr)); gap:10px; }

.sugeridas { margin-top:4px; }
.sugeridas-title { font-size:.75rem; color:var(--txt-3); margin-bottom:8px; text-transform:uppercase; letter-spacing:.04em; }
.sugeridas-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(240px, 1fr)); gap:6px; }
.sugerida-btn {
  text-align:left; background:var(--surf); border:1px solid var(--bord); border-radius:8px;
  padding:9px 13px; font-size:.78rem; color:var(--txt-2); cursor:pointer; font-family:'DM Sans',sans-serif;
  transition:.15s; line-height:1.4;
  &:hover { border-color:var(--prim-3); color:var(--prim); background:rgba(26,51,82,.03); }
}

/* Chat */
.chat-view { display:flex; flex-direction:column; flex:1; overflow:hidden; }
.chat-messages { flex:1; overflow-y:auto; padding:16px 24px; display:flex; flex-direction:column; gap:12px; }
.chat-msg { display:flex; &.user { justify-content:flex-end; } }
.chat-bubble {
  max-width:78%; padding:10px 14px; border-radius:12px;
  .chat-msg.assistant & { background:var(--surf); border:1px solid var(--bord); border-radius:3px 12px 12px 12px; }
  .chat-msg.user & { background:var(--prim); color:white; border-radius:12px 3px 12px 12px; }
}
.chat-content { font-size:.85rem; line-height:1.6; ::ng-deep { strong { color:var(--prim); } .chat-msg.user & strong { color:rgba(255,255,255,.9); } code { font-family:'DM Mono',monospace; font-size:.8em; background:var(--surf-2); padding:1px 4px; border-radius:3px; } ul { padding-left:16px; } li { margin:3px 0; } } }
.chat-msg.user .chat-content { color:white; }
.chat-time { display:block; font-size:.66rem; color:var(--txt-3); margin-top:4px; font-family:'DM Mono',monospace; }
.chat-msg.user .chat-time { color:rgba(255,255,255,.5); }
.typing { display:flex; gap:4px; padding:4px 0; span { width:6px; height:6px; border-radius:50%; background:var(--bord-2); animation:dots 1.2s infinite; } span:nth-child(2) { animation-delay:.2s; } span:nth-child(3) { animation-delay:.4s; } }
@keyframes dots { 0%,80%,100%{transform:scale(.7);opacity:.4} 40%{transform:scale(1);opacity:1} }

.chat-input-area { padding:12px 24px 16px; background:var(--surf); border-top:1px solid var(--bord); }
.sugeridas-chips { display:flex; gap:5px; flex-wrap:wrap; margin-bottom:8px; }
.chip { background:var(--surf-2); border:1px solid var(--bord); border-radius:20px; padding:4px 11px; font-size:.72rem; color:var(--txt-3); cursor:pointer; font-family:'DM Sans',sans-serif; transition:.15s; &:hover { border-color:var(--prim-3); color:var(--prim); } }
.input-row { display:flex; gap:8px; align-items:flex-end; background:var(--bg); border:1.5px solid var(--bord); border-radius:10px; padding:9px 9px 9px 14px; transition:.2s; &:focus-within { border-color:var(--prim-3); background:white; } }
.chat-input { flex:1; border:none; background:none; font-size:.85rem; font-family:'DM Sans',sans-serif; color:var(--txt); resize:none; outline:none; max-height:80px; &::placeholder { color:var(--txt-3); } &:disabled { opacity:.55; } }
.send-btn { width:32px; height:32px; border-radius:8px; border:none; background:var(--prim); color:white; cursor:pointer; display:flex; align-items:center; justify-content:center; flex-shrink:0; transition:.15s; &:hover:not(:disabled) { background:var(--prim-2); } &:disabled { opacity:.35; } }
.send-spinner { width:13px; height:13px; border:2px solid rgba(255,255,255,.3); border-top-color:white; border-radius:50%; animation:spin .7s linear infinite; }

/* Export */
.export-view { padding:24px; display:flex; flex-direction:column; gap:10px; max-width:600px; }
.export-card {
  display:flex; align-items:center; gap:14px; background:var(--surf); border:1px solid var(--bord);
  border-radius:12px; padding:16px 18px; cursor:pointer; transition:.15s;
  &:hover { border-color:var(--prim-3); box-shadow:var(--shadow); transform:translateY(-1px); }
  .export-icon { font-size:1.6rem; flex-shrink:0; }
  h3 { font-size:.88rem; font-weight:500; color:var(--txt); margin-bottom:3px; }
  p  { font-size:.76rem; color:var(--txt-3); }
  .export-arrow { color:var(--txt-3); font-size:1.1rem; flex-shrink:0; }
}
'@)
OK "analyzer.component (TS + HTML + SCSS)"

# ══════════════════════════════════════════════════════
# 3. ACTUALIZAR RUTAS Y SIDEBAR
# ══════════════════════════════════════════════════════
PASO "Actualizando rutas y sidebar"

[System.IO.File]::WriteAllText("$fe\app.routes.ts", @'
import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: '/chat', pathMatch: 'full' },
  { path: 'chat',         loadComponent: () => import('./features/chat/chat.component').then(m => m.ChatComponent) },
  { path: 'analyzer',     loadComponent: () => import('./features/analyzer/analyzer.component').then(m => m.AnalyzerComponent) },
  { path: 'repository',   loadComponent: () => import('./features/repository/repository.component').then(m => m.RepositoryComponent) },
  { path: 'documents',    loadComponent: () => import('./features/documents/documents.component').then(m => m.DocumentsComponent) },
  { path: 'my-templates', loadComponent: () => import('./features/my-templates/my-templates.component').then(m => m.MyTemplatesComponent) },
  { path: 'library',      loadComponent: () => import('./features/library/library.component').then(m => m.LibraryComponent) },
  { path: 'cases',        loadComponent: () => import('./features/cases/cases.component').then(m => m.CasesComponent) },
  { path: 'settings',     loadComponent: () => import('./features/settings/settings.component').then(m => m.SettingsComponent) },
  { path: 'auth/callback', loadComponent: () => import('./core/auth-callback/auth-callback.component').then(m => m.AuthCallbackComponent) },
  { path: '**', redirectTo: '/chat' }
];
'@)

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
    { path: '/chat',         label: 'Consulta IA',    icon: 'M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z' },
    { path: '/analyzer',     label: 'Analizar Doc',   icon: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4' },
    { path: '/repository',   label: 'Repositorio',    icon: 'M5 3a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V7.414A2 2 0 0020.414 6L15 .586A2 2 0 0013.586 0H5zm0 0M13 1v5a1 1 0 001 1h5' },
    { path: '/documents',    label: 'Generador',      icon: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z' },
    { path: '/my-templates', label: 'Mis Plantillas', icon: 'M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2' },
    { path: '/library',      label: 'Biblioteca',     icon: 'M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253' },
    { path: '/cases',        label: 'Casos',          icon: 'M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z' },
    { path: '/settings',     label: 'Config',         icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z' }
  ];
}
'@)
OK "Rutas y sidebar actualizados"

Write-Host @"

===============================================================
  Analisis de Documentos listo
===============================================================

  FUNCIONALIDADES:
  - Sube PDF, Word (.docx) o texto (.txt) hasta 20MB
  - Extrae texto automaticamente (pdf.js + mammoth)
  - Analisis IA: tipo, resumen, partes, fechas, montos,
    articulos bolivianos citados, riesgos, recomendacion
  - Chat sobre el documento: responde cualquier pregunta
  - Preguntas sugeridas segun el tipo de documento
  - Exportar analisis y chat a Word

  NUEVO en el sidebar: "Analizar Doc"
  Angular recarga automaticamente.
  Ir a: http://localhost:4200/analyzer

===============================================================
"@ -ForegroundColor Green
