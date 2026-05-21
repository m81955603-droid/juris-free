# JURIS-FREE Bolivia — Servidor de 5,737 muestras Word
# API FastAPI + Frontend Angular para navegar y usar las muestras
# PowerShell 7+

param([string]$Ruta = "C:\proyectos\juris-free")

$fe   = "$Ruta\frontend\src\app"
$back = "$Ruta\backend"
$ErrorActionPreference = "Continue"

function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }

Write-Host "`n  JURIS-FREE — Servidor de Muestras Word (5,737 archivos)`n" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════
# 1. RUTA FASTAPI PARA SERVIR ARCHIVOS
# ══════════════════════════════════════════════════════
PASO "Ruta FastAPI — servidor de archivos"

[System.IO.File]::WriteAllText("$back\api\routes\muestras.py", @'
"""
JURIS-FREE Bolivia — Servidor de Muestras Word
Sirve 5,737 archivos Word desde el filesystem local
"""

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, List
import os
import json

router = APIRouter()

MUESTRAS_BASE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    '..', '..', 'muestras'
)

# Cache del indice en memoria
_index_cache = None

# Mapeo de carpetas a categorias
CARPETA_CATEGORIA = {
    "1.- MATERIAL ANTIGUO":                                  "Material Antiguo",
    "2.- SUPER MALETA PAR ABOGADOS":                        "Super Maleta",
    "3.- DERECHO ACTUAL 1":                                  "Derecho Actual 1",
    "4.- DERECHO ACTUAL 2":                                  "Derecho Actual 2",
    "5.- DERECHO ACTUAL 3":                                  "Derecho Actual 3",
    "6.- CODIGO PRECESAL CIVIL CONCORDADO":                  "Codigo Procesal Civil",
    "12.- PROCEDIMIENTO_ FAMILIAR, NIÑA NIÑO ADOLECENTE":   "Procedimiento Familiar"
}

CARPETA_ICONO = {
    "1.- MATERIAL ANTIGUO":          "📁",
    "2.- SUPER MALETA PAR ABOGADOS": "💼",
    "3.- DERECHO ACTUAL 1":          "📚",
    "4.- DERECHO ACTUAL 2":          "📚",
    "5.- DERECHO ACTUAL 3":          "📚",
    "6.- CODIGO PRECESAL CIVIL CONCORDADO": "⚖",
    "12.- PROCEDIMIENTO_ FAMILIAR, NIÑA NIÑO ADOLECENTE": "👨‍👩‍👧"
}


class Muestra(BaseModel):
    id: str
    nombre: str
    carpeta: str
    subcarpeta: str
    categoria: str
    icono: str
    ruta_relativa: str
    tamanio: int


class MuestraIndex(BaseModel):
    total: int
    carpetas: List[dict]


def build_index() -> list:
    """Construye el indice de todos los archivos Word."""
    global _index_cache
    if _index_cache is not None:
        return _index_cache

    index = []
    if not os.path.exists(MUESTRAS_BASE):
        return index

    for carpeta_principal in sorted(os.listdir(MUESTRAS_BASE)):
        carpeta_path = os.path.join(MUESTRAS_BASE, carpeta_principal)
        if not os.path.isdir(carpeta_path):
            continue

        categoria  = CARPETA_CATEGORIA.get(carpeta_principal, carpeta_principal)
        icono      = CARPETA_ICONO.get(carpeta_principal, "📄")

        # Recorrer recursivamente
        for root, dirs, files in os.walk(carpeta_path):
            dirs.sort()
            for filename in sorted(files):
                if not filename.lower().endswith(('.docx', '.doc')):
                    continue

                full_path  = os.path.join(root, filename)
                rel_path   = os.path.relpath(full_path, MUESTRAS_BASE)
                subcarpeta = os.path.relpath(root, carpeta_path)
                if subcarpeta == '.':
                    subcarpeta = ''

                try:
                    tamanio = os.path.getsize(full_path)
                except:
                    tamanio = 0

                # ID unico basado en ruta
                doc_id = rel_path.replace('\\', '/').replace(' ', '_')

                index.append({
                    "id":             doc_id,
                    "nombre":         os.path.splitext(filename)[0],
                    "carpeta":        carpeta_principal,
                    "subcarpeta":     subcarpeta,
                    "categoria":      categoria,
                    "icono":          icono,
                    "ruta_relativa":  rel_path.replace('\\', '/'),
                    "tamanio":        tamanio
                })

    _index_cache = index
    return index


@router.get("/index")
async def get_index():
    """Indice completo con estadisticas por carpeta."""
    index = build_index()

    # Agrupar por carpeta
    carpetas = {}
    for doc in index:
        c = doc["carpeta"]
        if c not in carpetas:
            carpetas[c] = {
                "nombre":    c,
                "categoria": doc["categoria"],
                "icono":     doc["icono"],
                "total":     0,
                "subcarpetas": {}
            }
        carpetas[c]["total"] += 1

        sub = doc["subcarpeta"]
        if sub:
            if sub not in carpetas[c]["subcarpetas"]:
                carpetas[c]["subcarpetas"][sub] = 0
            carpetas[c]["subcarpetas"][sub] += 1

    return {
        "total":    len(index),
        "carpetas": list(carpetas.values())
    }


@router.get("/search")
async def search_muestras(
    q:       str            = Query("", description="Termino de busqueda"),
    carpeta: Optional[str]  = Query(None, description="Filtrar por carpeta"),
    page:    int            = Query(1, ge=1),
    limit:   int            = Query(50, le=200)
):
    """Busqueda paginada en el indice de muestras."""
    index = build_index()
    q_lower = q.lower().strip()

    # Filtrar
    results = []
    for doc in index:
        if carpeta and doc["carpeta"] != carpeta:
            continue
        if q_lower:
            if q_lower not in doc["nombre"].lower() and \
               q_lower not in doc["subcarpeta"].lower():
                continue
        results.append(doc)

    total = len(results)
    start = (page - 1) * limit
    end   = start + limit

    return {
        "total":   total,
        "page":    page,
        "limit":   limit,
        "pages":   (total + limit - 1) // limit,
        "results": results[start:end]
    }


@router.get("/download")
async def download_muestra(ruta: str = Query(..., description="Ruta relativa del archivo")):
    """Descarga un archivo Word por su ruta relativa."""
    # Seguridad: no permitir path traversal
    ruta_limpia = ruta.replace('..', '').replace('//', '/')
    full_path   = os.path.join(MUESTRAS_BASE, ruta_limpia.replace('/', os.sep))

    if not os.path.exists(full_path):
        raise HTTPException(404, f"Archivo no encontrado: {ruta}")

    if not full_path.startswith(MUESTRAS_BASE):
        raise HTTPException(403, "Acceso denegado")

    filename = os.path.basename(full_path)
    return FileResponse(
        path        = full_path,
        filename    = filename,
        media_type  = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )


@router.get("/stats")
async def get_stats():
    """Estadisticas del repositorio."""
    index = build_index()
    total_size = sum(d["tamanio"] for d in index)
    return {
        "total_archivos": len(index),
        "total_mb":       round(total_size / (1024 * 1024), 1),
        "carpetas":       len(set(d["carpeta"] for d in index))
    }
'@)
OK "muestras.py (API de archivos)"

# Actualizar main.py
[System.IO.File]::WriteAllText("$back\api\main.py", @'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
import logging
import os

load_dotenv(dotenv_path=r"C:\proyectos\juris-free\backend\.env", override=True)

from .routes import llm, embeddings, health, library, muestras

logging.basicConfig(level=logging.INFO)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.info("JURIS-FREE Bolivia API iniciando...")
    logging.info(f"Gemini:     {'OK' if os.getenv('GEMINI_API_KEY') else 'FALTA'}")
    logging.info(f"Groq:       {'OK' if os.getenv('GROQ_API_KEY') else 'FALTA'}")
    logging.info(f"Cerebras:   {'OK' if os.getenv('CEREBRAS_API_KEY') else 'FALTA'}")
    logging.info(f"OpenRouter: {'OK' if os.getenv('OPENROUTER_API_KEY') else 'FALTA'}")
    logging.info(f"SambaNova:  {'OK' if os.getenv('SAMBANOVA_API_KEY') else 'FALTA'}")
    # Precargar indice de muestras en background
    from .routes.muestras import build_index
    idx = build_index()
    logging.info(f"Muestras indexadas: {len(idx)} archivos Word")
    yield

app = FastAPI(title="JURIS-FREE Bolivia API", version="1.0.0", lifespan=lifespan)

app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"])

app.include_router(health.router)
app.include_router(llm.router,       prefix="/api/v1/llm",       tags=["LLM"])
app.include_router(embeddings.router, prefix="/api/v1/embeddings", tags=["Embeddings"])
app.include_router(library.router,   prefix="/api/v1/library",   tags=["Biblioteca"])
app.include_router(muestras.router,  prefix="/api/v1/muestras",  tags=["Muestras"])
'@)
OK "main.py actualizado"

# ══════════════════════════════════════════════════════
# 2. COMPONENTE ANGULAR — NAVEGADOR DE MUESTRAS
# ══════════════════════════════════════════════════════
PASO "Componente Angular — Repositorio de Muestras"
New-Item -ItemType Directory -Path "$fe\features\repository" -Force | Out-Null

[System.IO.File]::WriteAllText("$fe\features\repository\repository.component.ts", @'
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
'@)
OK "repository.component.ts"

[System.IO.File]::WriteAllText("$fe\features\repository\repository.component.html", @'
<div class="repo-layout">

  <!-- Header -->
  <header class="page-header">
    <div class="header-left">
      @if (view() !== 'home') {
        <button class="back-btn" (click)="goHome()">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="15" height="15">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
          </svg>
        </button>
      }
      <div>
        <h1 class="page-title">Repositorio de Muestras</h1>
        @if (stats()) {
          <p class="page-sub">{{ stats().total_archivos | number }} archivos Word · {{ stats().total_mb }} MB · {{ stats().carpetas }} carpetas</p>
        }
      </div>
    </div>
    <div class="header-right">
      <div class="search-box" [class.active]="searchQuery">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14">
          <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
        </svg>
        <input [(ngModel)]="searchQuery" (keydown)="onKeydown($event)" placeholder="Buscar en 5,737 muestras...">
        @if (searchQuery) {
          <button (click)="searchQuery=''; search()">×</button>
        }
      </div>
      @if (view() === 'carpeta') {
        <button class="btn-search" (click)="search()">Buscar</button>
      } @else {
        <button class="btn-search" (click)="globalSearch()">Buscar</button>
      }
    </div>
  </header>

  <div class="main-content">

    <!-- HOME -->
    @if (view() === 'home') {
      <div class="home-view">
        <div class="carpetas-grid">
          @for (cat of carpetas(); track cat.nombre) {
            <button class="carpeta-card" (click)="openCarpeta(cat)">
              <div class="carpeta-icon">{{ cat.icono }}</div>
              <div class="carpeta-info">
                <h3 class="carpeta-nombre">{{ cat.categoria }}</h3>
                <p class="carpeta-sub">{{ cat.nombre }}</p>
                <p class="carpeta-count">{{ cat.total | number }} documentos</p>
              </div>
              <div class="carpeta-arrow">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="16" height="16">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
                </svg>
              </div>
            </button>
          }
        </div>
      </div>
    }

    <!-- LISTA DE MUESTRAS -->
    @if (view() === 'carpeta') {
      <div class="list-view">
        <div class="list-header">
          @if (selectedCarpeta()) {
            <span class="list-cat-icon">{{ selectedCarpeta()!.icono }}</span>
            <div>
              <h2 class="list-title">{{ selectedCarpeta()!.categoria }}</h2>
              <p class="list-sub">{{ totalResults() | number }} documentos{{ searchQuery ? ' para "' + searchQuery + '"' : '' }}</p>
            </div>
          } @else {
            <div>
              <h2 class="list-title">Resultados de busqueda</h2>
              <p class="list-sub">{{ totalResults() | number }} resultados para "{{ searchQuery }}"</p>
            </div>
          }
        </div>

        @if (isLoading()) {
          <div class="loading-state">
            <div class="spinner"></div>
            <p>Cargando documentos...</p>
          </div>
        } @else {
          <div class="docs-list">
            @for (doc of results(); track doc.id) {
              <div class="doc-row">
                <div class="doc-row-icon">📄</div>
                <div class="doc-row-info">
                  <p class="doc-row-nombre">{{ doc.nombre }}</p>
                  <p class="doc-row-meta">
                    {{ doc.subcarpeta || doc.carpeta }}
                    · {{ formatSize(doc.tamanio) }}
                  </p>
                </div>
                <div class="doc-row-actions">
                  <button class="btn-download-sm" (click)="downloadOriginal(doc)" title="Descargar Word original">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="13" height="13">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                    </svg>
                    Word
                  </button>
                  <button class="btn-ai-sm" (click)="openWithAI(doc)" title="Completar con IA">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="13" height="13">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                    </svg>
                    IA
                  </button>
                </div>
              </div>
            }
          </div>

          <!-- Paginacion -->
          @if (totalPages() > 1) {
            <div class="pagination">
              <button class="page-btn" [disabled]="currentPage() === 1" (click)="search(currentPage() - 1)">‹</button>
              @for (p of getPages(); track p) {
                <button class="page-btn" [class.active]="p === currentPage()" (click)="search(p)">{{ p }}</button>
              }
              <button class="page-btn" [disabled]="currentPage() === totalPages()" (click)="search(currentPage() + 1)">›</button>
              <span class="page-info">Pag. {{ currentPage() }} de {{ totalPages() }}</span>
            </div>
          }
        }
      </div>
    }

    <!-- IA COMPLETE -->
    @if (view() === 'ai-complete') {
      <div class="ai-view">
        <div class="ai-header">
          <button class="btn-ghost" (click)="backToCarpeta()">← Volver</button>
          <div>
            <h2 class="ai-title">Completar con IA</h2>
            <p class="ai-sub">{{ selectedMuestra()?.nombre }}</p>
          </div>
        </div>

        @if (!aiResult()) {
          <div class="ai-form">
            <label class="field-label">Describe los datos especificos del documento</label>
            <p class="field-hint">Indica las partes, fechas, montos, hechos y cualquier dato especifico que necesitas en el documento</p>
            <textarea
              class="ai-textarea"
              [(ngModel)]="aiInstructions"
              [placeholder]="'Ej: Completar para ' + (selectedMuestra()?.nombre || 'este documento') + '. Indicar: partes involucradas con CI, fechas, montos, ciudad, y cualquier dato especifico del caso...'"
              rows="6">
            </textarea>
            <button class="btn-generate" (click)="completeWithAI()" [disabled]="isGenerating() || !aiInstructions.trim()">
              @if (isGenerating()) {
                <div class="btn-spinner"></div>
                Generando documento...
              } @else {
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="15" height="15">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                </svg>
                Generar con IA
              }
            </button>
          </div>
        } @else {
          <div class="ai-result">
            <div class="result-toolbar">
              <button class="btn-ghost" (click)="aiResult.set(''); aiInstructions = ''">Regenerar</button>
              <div class="download-btns">
                <button class="btn-dl word" (click)="downloadAiWord()">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="13" height="13">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                  </svg>
                  Descargar Word
                </button>
                <button class="btn-dl pdf" (click)="downloadAiPdf()">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="13" height="13">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                  </svg>
                  Descargar PDF
                </button>
              </div>
            </div>
            <div class="result-doc">
              <div class="doc-content" [innerHTML]="renderMarkdown(aiResult())"></div>
            </div>
          </div>
        }
      </div>
    }

  </div>
</div>
'@)

[System.IO.File]::WriteAllText("$fe\features\repository\repository.component.scss", @'
:host { display:flex; flex-direction:column; height:100vh; overflow:hidden; }
.repo-layout { display:flex; flex-direction:column; height:100vh; overflow:hidden; background:var(--bg); }

.page-header {
  display:flex; align-items:center; justify-content:space-between; gap:12px;
  padding:12px 24px; background:var(--surf); border-bottom:1px solid var(--bord);
  flex-shrink:0; flex-wrap:wrap;
}
.header-left { display:flex; align-items:center; gap:10px; }
.back-btn {
  background:none; border:none; cursor:pointer; color:var(--txt-3);
  padding:6px; border-radius:8px; display:flex; align-items:center; transition:.15s;
  &:hover { background:var(--surf-2); color:var(--prim); }
}
.page-title { font-family:"Playfair Display",serif; font-size:1.05rem; font-weight:600; color:var(--txt); }
.page-sub { font-size:.7rem; color:var(--txt-3); margin-top:1px; }
.header-right { display:flex; align-items:center; gap:8px; }

.search-box {
  display:flex; align-items:center; gap:7px; background:var(--bg); border:1.5px solid var(--bord);
  border-radius:9px; padding:8px 13px; transition:.2s; min-width:280px;
  &:focus-within, &.active { border-color:var(--prim-3); background:white; }
  input { border:none; background:none; font-size:.82rem; font-family:'DM Sans',sans-serif; color:var(--txt); outline:none; flex:1; &::placeholder { color:var(--txt-3); } }
  button { background:none; border:none; color:var(--txt-3); cursor:pointer; font-size:1rem; }
  svg { color:var(--txt-3); flex-shrink:0; }
}
.btn-search {
  background:var(--prim); color:white; border:none; border-radius:8px; padding:8px 18px;
  font-size:.8rem; font-family:'DM Sans',sans-serif; cursor:pointer; transition:.15s; white-space:nowrap;
  &:hover { background:var(--prim-2); }
}

.main-content { flex:1; overflow-y:auto; }

/* Home */
.home-view { padding:20px 24px; }
.carpetas-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(280px, 1fr)); gap:10px; }
.carpeta-card {
  display:flex; align-items:center; gap:14px; background:var(--surf);
  border:1px solid var(--bord); border-radius:12px; padding:16px 18px;
  cursor:pointer; text-align:left; transition:.15s; font-family:'DM Sans',sans-serif; width:100%;
  &:hover { border-color:var(--prim-3); box-shadow:var(--shadow-md); transform:translateY(-1px); }
}
.carpeta-icon { font-size:2rem; flex-shrink:0; }
.carpeta-info { flex:1; }
.carpeta-nombre { font-size:.9rem; font-weight:500; color:var(--txt); margin-bottom:2px; }
.carpeta-sub { font-size:.72rem; color:var(--txt-3); margin-bottom:3px; }
.carpeta-count { font-size:.75rem; color:var(--gold); font-weight:500; }
.carpeta-arrow { color:var(--txt-3); }

/* Lista */
.list-view { padding:16px 24px; display:flex; flex-direction:column; gap:12px; }
.list-header { display:flex; align-items:center; gap:12px; }
.list-cat-icon { font-size:1.8rem; flex-shrink:0; }
.list-title { font-family:"Playfair Display",serif; font-size:1rem; font-weight:600; color:var(--txt); }
.list-sub { font-size:.75rem; color:var(--txt-3); margin-top:2px; }

.loading-state { display:flex; flex-direction:column; align-items:center; gap:12px; padding:48px; }
.spinner { width:32px; height:32px; border:2px solid var(--bord); border-top-color:var(--prim); border-radius:50%; animation:spin .8s linear infinite; }
@keyframes spin { to { transform:rotate(360deg); } }

.docs-list { display:flex; flex-direction:column; gap:3px; }
.doc-row {
  display:flex; align-items:center; gap:10px; background:var(--surf);
  border:1px solid var(--bord); border-radius:8px; padding:9px 14px;
  transition:.12s;
  &:hover { border-color:var(--bord-2); background:var(--surf-2); }
}
.doc-row-icon { font-size:1rem; flex-shrink:0; color:var(--txt-3); }
.doc-row-info { flex:1; min-width:0; }
.doc-row-nombre { font-size:.82rem; font-weight:400; color:var(--txt); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.doc-row-meta { font-size:.7rem; color:var(--txt-3); margin-top:1px; }
.doc-row-actions { display:flex; gap:5px; flex-shrink:0; }

.btn-download-sm {
  display:flex; align-items:center; gap:4px; background:#1a5296; color:white;
  border:none; border-radius:6px; padding:5px 10px; font-size:.72rem;
  font-family:'DM Sans',sans-serif; cursor:pointer; transition:.15s; white-space:nowrap;
  &:hover { background:#0f3a72; }
}
.btn-ai-sm {
  display:flex; align-items:center; gap:4px; background:var(--gold); color:white;
  border:none; border-radius:6px; padding:5px 10px; font-size:.72rem;
  font-family:'DM Sans',sans-serif; cursor:pointer; transition:.15s; white-space:nowrap;
  &:hover { background:#a07820; }
}

/* Paginacion */
.pagination { display:flex; align-items:center; gap:4px; padding:12px 0; flex-wrap:wrap; }
.page-btn {
  min-width:32px; height:32px; border:1px solid var(--bord); background:var(--surf);
  border-radius:6px; font-size:.78rem; cursor:pointer; font-family:'DM Sans',sans-serif;
  color:var(--txt-2); transition:.15s; display:flex; align-items:center; justify-content:center;
  &:hover:not(:disabled) { border-color:var(--prim-3); color:var(--prim); }
  &.active { background:var(--prim); border-color:var(--prim); color:white; }
  &:disabled { opacity:.4; cursor:not-allowed; }
}
.page-info { font-size:.72rem; color:var(--txt-3); margin-left:6px; font-family:'DM Mono',monospace; }

/* AI */
.ai-view { padding:20px 24px; display:flex; flex-direction:column; gap:16px; max-width:800px; }
.ai-header { display:flex; align-items:center; gap:14px; padding-bottom:14px; border-bottom:1px solid var(--bord); }
.ai-title { font-family:"Playfair Display",serif; font-size:1rem; font-weight:600; color:var(--txt); }
.ai-sub { font-size:.75rem; color:var(--txt-3); margin-top:2px; }

.btn-ghost {
  display:flex; align-items:center; gap:6px; background:none; border:1px solid var(--bord);
  color:var(--txt-2); font-size:.78rem; padding:6px 12px; border-radius:8px; cursor:pointer;
  font-family:'DM Sans',sans-serif; transition:.15s; white-space:nowrap;
  &:hover { background:var(--surf-2); color:var(--txt); }
}

.ai-form { display:flex; flex-direction:column; gap:10px; }
.field-label { font-size:.82rem; font-weight:500; color:var(--txt-2); }
.field-hint { font-size:.75rem; color:var(--txt-3); }
.ai-textarea {
  border:1.5px solid var(--bord); border-radius:10px; padding:12px 14px; font-size:.85rem;
  font-family:'DM Sans',sans-serif; color:var(--txt); resize:vertical; min-height:130px;
  outline:none; transition:.2s;
  &:focus { border-color:var(--prim-3); background:white; }
  &::placeholder { color:var(--txt-3); font-size:.8rem; }
}
.btn-generate {
  display:flex; align-items:center; gap:8px; background:var(--prim); color:white; border:none;
  border-radius:10px; padding:12px 24px; font-size:.85rem; font-family:'DM Sans',sans-serif;
  cursor:pointer; transition:.15s; align-self:flex-start;
  &:hover:not(:disabled) { background:var(--prim-2); }
  &:disabled { opacity:.5; cursor:not-allowed; }
}
.btn-spinner { width:14px; height:14px; border:2px solid rgba(255,255,255,.3); border-top-color:white; border-radius:50%; animation:spin .7s linear infinite; }

.ai-result { display:flex; flex-direction:column; gap:12px; }
.result-toolbar { display:flex; justify-content:space-between; align-items:center; background:var(--surf); border:1px solid var(--bord); border-radius:10px; padding:10px 14px; }
.download-btns { display:flex; gap:8px; }
.btn-dl { display:flex; align-items:center; gap:5px; border:none; border-radius:7px; padding:7px 13px; font-size:.76rem; font-family:'DM Sans',sans-serif; cursor:pointer; transition:.15s; &.word { background:#1a5296; color:white; &:hover { background:#0f3a72; } } &.pdf { background:#c0392b; color:white; &:hover { background:#962d22; } } }
.result-doc { overflow-y:auto; }
.doc-content { background:var(--surf); border:1px solid var(--bord); border-radius:8px; padding:32px 40px; font-size:.88rem; line-height:1.7; color:var(--txt); ::ng-deep { h3 { font-family:"Playfair Display",serif; font-size:.95rem; font-weight:600; color:var(--prim); margin:16px 0 6px; border-bottom:1px solid var(--bord); padding-bottom:4px; } strong { color:var(--prim); font-weight:500; } code { font-family:'DM Mono',monospace; font-size:.8em; background:var(--surf-2); padding:1px 5px; border-radius:3px; } ul { padding-left:18px; margin:6px 0; } li { margin:3px 0; } p { margin:6px 0; } } }
'@)
OK "repository.component (HTML + SCSS)"

# ══════════════════════════════════════════════════════
# 3. ACTUALIZAR RUTAS
# ══════════════════════════════════════════════════════
PASO "Actualizando rutas"

[System.IO.File]::WriteAllText("$fe\app.routes.ts", @'
import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: '/chat', pathMatch: 'full' },
  { path: 'chat',         loadComponent: () => import('./features/chat/chat.component').then(m => m.ChatComponent) },
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
OK "app.routes.ts"

Write-Host @"

===============================================================
  Repositorio de 5,737 Muestras listo
===============================================================

  COMO FUNCIONA:
  - El backend sirve los archivos directamente desde el disco
  - No hay limite de tamanio (5,737 archivos, cualquier cantidad)
  - Busqueda paginada (50 por pagina) con filtros por carpeta
  - Descarga del Word original con un clic
  - Completar con IA: describe el caso y genera el documento

  CARPETAS DISPONIBLES:
  - Material Antiguo        (2,199 docs)
  - Super Maleta Abogados   (354 docs)
  - Derecho Actual 1        (340 docs)
  - Derecho Actual 2        (1,826 docs)
  - Derecho Actual 3        (987 docs)
  - Codigo Procesal Civil   (25 docs)
  - Procedimiento Familiar  (4 docs)

  PASOS PARA ACTIVAR:
  1. Reiniciar backend (Ctrl+C luego uvicorn)
  2. Angular recarga automaticamente
  3. Ir a: http://localhost:4200/repository

===============================================================
"@ -ForegroundColor Green
