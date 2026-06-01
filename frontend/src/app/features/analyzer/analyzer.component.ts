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

      if (ext === '.txt') {
        texto = await file.text();
      } else {
        texto = await this.extractFromBackend(file);
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

  private async extractFromBackend(file: File): Promise<string> {
    const formData = new FormData();
    formData.append('file', file);
    const resp = await fetch(
      'https://juris-free-backend.onrender.com/api/v1/documents/extract-text',
      { method: 'POST', body: formData }
    );
    if (!resp.ok) {
      const err = await resp.json();
      throw new Error(err.detail || 'Error en el servidor');
    }
    const data = await resp.json();
    return data.text || '';
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