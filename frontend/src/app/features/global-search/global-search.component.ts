import { Component, signal, inject, ElementRef, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '../../../environments/environment';
import { Subject, debounceTime, distinctUntilChanged } from 'rxjs';

interface SearchHit {
  tipo: 'caso' | 'nota' | 'cliente' | 'norma';
  id: string;
  titulo: string;
  subtitulo?: string;
  snippet?: string;
  url: string;
  score: number;
}

@Component({
  selector: 'app-global-search',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './global-search.component.html',
  styleUrls: ['./global-search.component.scss']
})
export class GlobalSearchComponent {
  private http   = inject(HttpClient);
  private router = inject(Router);

  query      = '';
  results    = signal<SearchHit[]>([]);
  isSearching = signal(false);
  hasSearched = signal(false);
  private search$ = new Subject<string>();

  readonly tipoLabels: Record<string, string> = {
    caso: 'Caso', nota: 'Nota', cliente: 'Cliente', norma: 'Ley / Artículo'
  };

  readonly tipoIcons: Record<string, string> = {
    caso: '⚖', nota: '📝', cliente: '👤', norma: '📋'
  };

  readonly tipoColors: Record<string, string> = {
    caso: '#1a5296', nota: '#6c3483', cliente: '#1a6b3c', norma: '#c4922a'
  };

  constructor() {
    this.search$.pipe(
      debounceTime(400),
      distinctUntilChanged()
    ).subscribe(q => this.doSearch(q));
  }

  onInput() { this.search$.next(this.query); }

  onKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') this.doSearch(this.query);
    if (e.key === 'Escape') { this.query = ''; this.results.set([]); this.hasSearched.set(false); }
  }

  doSearch(q: string) {
    if (!q.trim() || q.length < 2) { this.results.set([]); return; }
    this.isSearching.set(true);
    this.hasSearched.set(true);
    this.http.get<SearchHit[]>(`${environment.apiUrl}/api/v1/search`, { params: { q, limit: '16' } })
      .subscribe({
        next: r => { this.results.set(r); this.isSearching.set(false); },
        error: () => { this.isSearching.set(false); }
      });
  }

  navigate(hit: SearchHit) {
    this.router.navigate([hit.url]);
  }

  get grupos(): { tipo: string; hits: SearchHit[] }[] {
    const mapa: Record<string, SearchHit[]> = {};
    for (const h of this.results()) {
      if (!mapa[h.tipo]) mapa[h.tipo] = [];
      mapa[h.tipo].push(h);
    }
    const orden = ['caso', 'cliente', 'nota', 'norma'];
    return orden.filter(t => mapa[t]).map(t => ({ tipo: t, hits: mapa[t] }));
  }

  limpiar() { this.query = ''; this.results.set([]); this.hasSearched.set(false); }
}
