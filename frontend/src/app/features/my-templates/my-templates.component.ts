import { Component, signal, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

interface Plantilla {
  id: string;
  nombre: string;
  tipo_documento: string;
  tono: string;
  resumen_estilo: string;
  system_prompt: string;
  variables: string;
  ficha_estilo: string;
  created_at: string;
}

interface FichaEstilo {
  tono: string;
  estructura_preferida: string;
  conectores_frecuentes: string[];
  nivel_tecnico: string;
  preferencias_formato: Record<string, boolean>;
  variables_detectadas: string[];
  tipo_documento: string;
  resumen_estilo: string;
  system_prompt_personalizado: string;
}

@Component({
  selector: 'app-my-templates',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './my-templates.component.html',
  styleUrls: ['./my-templates.component.scss']
})
export class MyTemplatesComponent implements OnInit {
  private http = inject(HttpClient);
  private api  = environment.apiUrl + '/api/v1/documents';

  plantillas    = signal<Plantilla[]>([]);
  cargando      = signal(false);
  analizando    = signal(false);
  selectedFile  = signal<File | null>(null);
  nombre        = '';
  dragOver      = signal(false);
  fichaActual   = signal<{ ficha: FichaEstilo; nombre: string } | null>(null);
  vista         = signal<'lista' | 'detalle'>('lista');

  ngOnInit() { this.cargar(); }

  cargar() {
    this.cargando.set(true);
    this.http.get<Plantilla[]>(`${this.api}/plantillas`).subscribe({
      next: data => { this.plantillas.set(data); this.cargando.set(false); },
      error: () => this.cargando.set(false)
    });
  }

  onDragOver(e: DragEvent) { e.preventDefault(); this.dragOver.set(true); }
  onDragLeave() { this.dragOver.set(false); }
  onDrop(e: DragEvent) {
    e.preventDefault(); this.dragOver.set(false);
    const file = e.dataTransfer?.files[0];
    if (file) this.selectedFile.set(file);
  }
  onFileSelected(e: Event) {
    const input = e.target as HTMLInputElement;
    if (input.files?.[0]) this.selectedFile.set(input.files[0]);
  }

  async analizar() {
    const file = this.selectedFile();
    if (!file || !this.nombre.trim()) return;

    this.analizando.set(true);
    const formData = new FormData();
    formData.append('file', file);
    formData.append('nombre', this.nombre.trim());

    this.http.post<any>(`${this.api}/plantillas/analizar`, formData).subscribe({
      next: result => {
        this.analizando.set(false);
        this.fichaActual.set({ ficha: result.ficha, nombre: result.nombre });
        this.vista.set('detalle');
        this.cargar();
        this.selectedFile.set(null);
        this.nombre = '';
      },
      error: err => {
        this.analizando.set(false);
        alert('Error analizando: ' + (err.error?.detail || err.message));
      }
    });
  }

  verDetalle(p: Plantilla) {
    try {
      const ficha = JSON.parse(p.ficha_estilo) as FichaEstilo;
      this.fichaActual.set({ ficha, nombre: p.nombre });
      this.vista.set('detalle');
    } catch { }
  }

  eliminar(id: string) {
    if (!confirm('¿Eliminar esta plantilla?')) return;
    this.http.delete(`${this.api}/plantillas/${id}`).subscribe(() => {
      this.cargar();
      if (this.vista() === 'detalle') { this.vista.set('lista'); this.fichaActual.set(null); }
    });
  }

  volver() { this.vista.set('lista'); this.fichaActual.set(null); }

  getFormatKeys(pref: Record<string, boolean>): string[] {
    return Object.keys(pref).filter(k => pref[k]);
  }

  formatKey(k: string): string {
    const m: Record<string, string> = {
      usa_negritas: 'Negritas', usa_numeracion: 'Numeración',
      usa_sangria_francesa: 'Sangría francesa', citas_al_pie: 'Citas al pie'
    };
    return m[k] || k;
  }

  getTipoIcon(tipo: string): string {
    const icons: Record<string, string> = {
      contrato: '📋', demanda: '⚖', memorial: '📄',
      poder: '🏛', denuncia: '🚨', general: '📝'
    };
    return icons[tipo] || '📝';
  }

  getTonoBadge(tono: string): string {
    const m: Record<string, string> = {
      formal: 'tono-formal', conciliador: 'tono-conciliador',
      agresivo: 'tono-agresivo', tecnico: 'tono-tecnico', notarial: 'tono-notarial'
    };
    return m[tono] || 'tono-formal';
  }
}
