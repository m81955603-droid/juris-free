import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

interface SearchResult {
  id: string;
  tipo: string;
  titulo: string;
  area: string;
  resumen: string;
  articulos_relevantes: { numero: string; texto: string; relevancia: number }[];
  score: number;
}

interface SemanticResult {
  norma_titulo: string;
  articulo: string;
  texto: string;
  area: string | null;
  tipo: string | null;
  similitud: number;
}

interface Norma {
  id: string;
  tipo: string;
  titulo: string;
  area: string;
  fecha: string;
  total_articulos: number;
}

interface LibStats {
  total_normas: number;
  total_articulos_indexados: number;
  por_area: Record<string, number>;
  por_tipo: Record<string, number>;
  fuentes: string[];
}

@Component({
  selector: 'app-library',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './library.component.html',
  styleUrls: ['./library.component.scss']
})
export class LibraryComponent implements OnInit {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl + '/api/v1/library';

  searchQuery      = '';
  selectedArea     = '';
  selectedTipo     = '';
  searchMode       = signal<'semantica' | 'clasica'>('semantica');
  isSearching      = signal(false);
  results          = signal<SearchResult[]>([]);
  semanticResults  = signal<SemanticResult[]>([]);
  normas           = signal<Norma[]>([]);
  stats            = signal<LibStats | null>(null);
  selectedNorma    = signal<any>(null);
  view             = signal<'home' | 'search' | 'detail'>('home');
  hasSearched      = signal(false);

  readonly areas = [
    { valor: '',               label: 'Todas las áreas' },
    { valor: 'civil',          label: 'Civil' },
    { valor: 'penal',          label: 'Penal' },
    { valor: 'laboral',        label: 'Laboral' },
    { valor: 'constitucional', label: 'Constitucional' },
    { valor: 'familiar',       label: 'Familiar' },
    { valor: 'administrativo', label: 'Administrativo' }
  ];

  readonly tipos = [
    { valor: '',             label: 'Todos los tipos' },
    { valor: 'constitucion', label: 'Constitución' },
    { valor: 'codigo',       label: 'Código' },
    { valor: 'ley',          label: 'Ley' },
    { valor: 'sentencia',    label: 'Sentencia' }
  ];

  readonly areaColors: Record<string, string> = {
    'civil':          '#1a5296',
    'penal':          '#c0392b',
    'laboral':        '#1a6b3c',
    'constitucional': '#6c3483',
    'familiar':       '#c4922a',
    'administrativo': '#2e86ab'
  };

  ngOnInit(): void {
    this.loadStats();
    this.loadNormas();
  }

  loadStats(): void {
    this.http.get<LibStats>(this.apiUrl + '/stats').subscribe({
      next: s => this.stats.set(s),
      error: () => {}
    });
  }

  loadNormas(): void {
    this.http.get<Norma[]>(this.apiUrl + '/normas').subscribe({
      next: n => this.normas.set(n),
      error: () => {}
    });
  }

  search(): void {
    if (!this.searchQuery.trim()) return;
    this.isSearching.set(true);
    this.hasSearched.set(true);
    this.view.set('search');

    if (this.searchMode() === 'semantica') {
      const params: any = { q: this.searchQuery, limit: 8 };
      if (this.selectedArea) params.area = this.selectedArea;
      this.http.get<SemanticResult[]>(this.apiUrl + '/search-semantic', { params }).subscribe({
        next: r => { this.semanticResults.set(r); this.isSearching.set(false); },
        error: () => { this.isSearching.set(false); }
      });
    } else {
      const params: any = { q: this.searchQuery };
      if (this.selectedArea) params.area = this.selectedArea;
      if (this.selectedTipo) params.tipo = this.selectedTipo;
      this.http.get<SearchResult[]>(this.apiUrl + '/search', { params }).subscribe({
        next: r => { this.results.set(r); this.isSearching.set(false); },
        error: () => { this.isSearching.set(false); }
      });
    }
  }

  setMode(mode: 'semantica' | 'clasica'): void {
    this.searchMode.set(mode);
    this.hasSearched.set(false);
    this.results.set([]);
    this.semanticResults.set([]);
    this.searchQuery = '';
  }

  openNorma(id: string): void {
    this.http.get(this.apiUrl + '/norma/' + id).subscribe({
      next: n => { this.selectedNorma.set(n); this.view.set('detail'); },
      error: () => {}
    });
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter') this.search();
  }

  getAreaColor(area: string): string {
    return this.areaColors[area] || '#7a7268';
  }

  getAreaLabel(area: string): string {
    return this.areas.find(a => a.valor === area)?.label || area;
  }

  getTipoIcon(tipo: string): string {
    const icons: Record<string, string> = {
      'constitucion': '🏛',
      'codigo':       '📚',
      'ley':          '📋',
      'decreto':      '📜',
      'sentencia':    '⚖'
    };
    return icons[tipo] || '📄';
  }

  getSimilitudLabel(s: number): string {
    if (s >= 0.75) return 'Alta relevancia';
    if (s >= 0.55) return 'Relevante';
    return 'Relacionado';
  }

  getSimilitudClass(s: number): string {
    if (s >= 0.75) return 'sim-alta';
    if (s >= 0.55) return 'sim-media';
    return 'sim-baja';
  }

  getObjectKeys(obj: Record<string, number>): string[] {
    return obj ? Object.keys(obj) : [];
  }

  goHome(): void {
    this.view.set('home');
    this.hasSearched.set(false);
    this.selectedNorma.set(null);
    this.results.set([]);
    this.semanticResults.set([]);
    this.searchQuery = '';
  }

  back(): void {
    if (this.view() === 'detail') {
      this.view.set(this.hasSearched() ? 'search' : 'home');
      this.selectedNorma.set(null);
    } else {
      this.goHome();
    }
  }
}
