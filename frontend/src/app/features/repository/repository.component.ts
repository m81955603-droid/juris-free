import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { DocumentService } from '../../core/services/document.service';

interface Carpeta {
  nombre: string;
  categoria: string;
  icono: string;
  total: number;
  subcarpetas: Record<string, number>;
}

interface Muestra {
  id: string;
  nombre: string;
  carpeta: string;
  subcarpeta: string;
  categoria: string;
  icono: string;
  ruta_relativa: string;
  tamanio: number;
}

interface SearchResponse {
  total: number;
  page: number;
  pages: number;
  results: Muestra[];
}

type View = 'home' | 'carpeta' | 'ai-complete';

@Component({
  selector:    'app-repository',
  standalone:  true,
  imports:     [CommonModule, FormsModule],
  templateUrl: './repository.component.html',
  styleUrls:   ['./repository.component.scss']
})
export class RepositoryComponent implements OnInit {
  private http   = inject(HttpClient);
  private llm    = inject(LlmProxyService);
  private docSvc = inject(DocumentService);
  private api    = environment.apiUrl + '/api/v1/muestras';

  view              = signal<View>('home');
  carpetas          = signal<Carpeta[]>([]);
  selectedCarpeta   = signal<Carpeta | null>(null);
  results           = signal<Muestra[]>([]);
  totalResults      = signal(0);
  totalPages        = signal(0);
  currentPage       = signal(1);
  searchQuery       = '';
  isLoading         = signal(false);
  isGenerating      = signal(false);
  selectedMuestra   = signal<Muestra | null>(null);
  aiInstructions    = '';
  aiResult          = signal('');
  stats             = signal<any>(null);

  ngOnInit(): void {
    this.loadIndex();
    this.loadStats();
  }

  loadIndex(): void {
    this.http.get<any>(this.api + '/index').subscribe({
      next: data => this.carpetas.set(data.carpetas),
      error: err => console.error('Error cargando indice:', err)
    });
  }

  loadStats(): void {
    this.http.get<any>(this.api + '/stats').subscribe({
      next: s => this.stats.set(s),
      error: () => {}
    });
  }

  openCarpeta(carpeta: Carpeta): void {
    this.selectedCarpeta.set(carpeta);
    this.searchQuery = '';
    this.currentPage.set(1);
    this.view.set('carpeta');
    this.search();
  }

  search(page = 1): void {
    this.isLoading.set(true);
    this.currentPage.set(page);

    const params: any = { page, limit: 50 };
    if (this.searchQuery.trim()) params.q = this.searchQuery;
    if (this.selectedCarpeta()) params.carpeta = this.selectedCarpeta()!.nombre;

    this.http.get<SearchResponse>(this.api + '/search', { params }).subscribe({
      next: resp => {
        this.results.set(resp.results);
        this.totalResults.set(resp.total);
        this.totalPages.set(resp.pages);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  globalSearch(): void {
    if (!this.searchQuery.trim()) return;
    this.selectedCarpeta.set(null);
    this.view.set('carpeta');
    this.search();
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter') {
      if (this.view() === 'home') this.globalSearch();
      else this.search();
    }
  }

  downloadOriginal(muestra: Muestra): void {
    const url = `${this.api}/download?ruta=${encodeURIComponent(muestra.ruta_relativa)}`;
    const a = document.createElement('a');
    a.href = url;
    a.download = muestra.nombre + '.docx';
    a.click();
  }

  openWithAI(muestra: Muestra): void {
    this.selectedMuestra.set(muestra);
    this.aiInstructions = '';
    this.aiResult.set('');
    this.view.set('ai-complete');
  }

  async completeWithAI(): Promise<void> {
    const muestra = this.selectedMuestra();
    if (!muestra || !this.aiInstructions.trim()) return;

    this.isGenerating.set(true);

    const prompt = `Eres un abogado boliviano experto. Tienes esta muestra de documento legal como referencia:

Nombre del documento: "${muestra.nombre}"
Categoria: ${muestra.categoria}
Carpeta: ${muestra.carpeta}

INSTRUCCIONES DEL USUARIO:
${this.aiInstructions}

TAREA:
Genera un documento legal boliviano completo basado en el tipo de documento indicado.
- Usa la estructura tipica de ese tipo de documento en Bolivia
- Cita los articulos bolivianos correctos y vigentes
- Completa todos los datos especificos indicados por el usuario
- El resultado debe ser profesional y listo para usar

Genera el documento completo.`;

    this.llm.chat([{ role: 'user', content: prompt }]).subscribe({
      next: resp => {
        this.aiResult.set(resp.content);
        this.isGenerating.set(false);
      },
      error: err => {
        this.aiResult.set('Error: ' + err.message);
        this.isGenerating.set(false);
      }
    });
  }

  async downloadAiWord(): Promise<void> {
    const m = this.selectedMuestra();
    if (!m || !this.aiResult()) return;
    await this.docSvc.generateLegalDocument({ titulo: m.nombre, contenido: this.aiResult() });
  }

  async downloadAiPdf(): Promise<void> {
    const m = this.selectedMuestra();
    if (!m || !this.aiResult()) return;
    await this.docSvc.exportChatToPdf(this.aiResult(), m.nombre);
  }

  goHome(): void {
    this.view.set('home');
    this.selectedCarpeta.set(null);
    this.selectedMuestra.set(null);
    this.results.set([]);
    this.searchQuery = '';
    this.aiResult.set('');
  }

  backToCarpeta(): void {
    this.view.set('carpeta');
    this.aiResult.set('');
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

  formatSize(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  getPages(): number[] {
    const total = this.totalPages();
    const current = this.currentPage();
    const pages: number[] = [];
    const start = Math.max(1, current - 2);
    const end   = Math.min(total, current + 2);
    for (let i = start; i <= end; i++) pages.push(i);
    return pages;
  }
}