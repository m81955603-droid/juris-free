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

  searchQuery    = '';
  selectedArea   = '';
  selectedTipo   = '';
  isSearching    = signal(false);
  results        = signal<SearchResult[]>([]);
  normas         = signal<Norma[]>([]);
  stats          = signal<LibStats | null>(null);
  selectedNorma  = signal<any>(null);
  view           = signal<'search' | 'browse' | 'detail'>('search');
  hasSearched    = signal(false);

  readonly areas = [
    { valor: '',               label: 'Todas las areas' },
    { valor: 'civil',          label: 'Derecho Civil' },
    { valor: 'penal',          label: 'Derecho Penal' },
    { valor: 'laboral',        label: 'Derecho Laboral' },
    { valor: 'constitucional', label: 'Derecho Constitucional' },
    { valor: 'familiar',       label: 'Derecho Familiar' },
    { valor: 'administrativo', label: 'Derecho Administrativo' }
  ];

  readonly tipos = [
    { valor: '',             label: 'Todos los tipos' },
    { valor: 'constitucion', label: 'Constitucion' },
    { valor: 'codigo',       label: 'Codigo' },
    { valor: 'ley',          label: 'Ley' },
    { valor: 'sentencia',    label: 'Sentencia' }
  ];

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

    const params: any = { q: this.searchQuery };
    if (this.selectedArea) params.area = this.selectedArea;
    if (this.selectedTipo) params.tipo = this.selectedTipo;

    this.http.get<SearchResult[]>(this.apiUrl + '/search', { params }).subscribe({
      next: r => { this.results.set(r); this.isSearching.set(false); this.view.set('search'); },
      error: () => { this.isSearching.set(false); }
    });
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
    const colors: Record<string, string> = {
      'civil':          '#1a5296',
      'penal':          '#c0392b',
      'laboral':        '#1a6b3c',
      'constitucional': '#6c3483',
      'familiar':       '#c4922a',
      'administrativo': '#2e86ab'
    };
    return colors[area] || '#7a7268';
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

  getObjectKeys(obj: Record<string, number>): string[] {
    return obj ? Object.keys(obj) : [];
  }

  back(): void {
    this.view.set('search');
    this.selectedNorma.set(null);
  }
}