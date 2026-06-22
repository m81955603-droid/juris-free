import { Component, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule, ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { CasesService, Caso } from '../../core/services/cases.service';
import { CalendarService } from '../../core/services/calendar.service';

interface PlazoResult {
  tipo_plazo: string;
  norma: string;
  dias_habiles: number;
  fecha_inicio: string;
  fecha_vence: string;
  dias_quedan: number;
  evento_sugerido: any;
}

@Component({
  selector: 'app-cases',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule],
  templateUrl: './cases.component.html',
  styleUrls: ['./cases.component.scss']
})
export class CasesComponent implements OnInit {
  casos            = signal<Caso[]>([]);
  casoSeleccionado = signal<any>(null);
  vista            = signal<'lista' | 'detalle' | 'nuevo' | 'plazo'>('lista');
  cargando         = signal(false);
  busqueda         = '';
  filtroEstado     = '';
  filtroTipo       = '';
  nuevaNota        = '';
  form:            FormGroup;
  plazoForm:       FormGroup;
  resultadoPlazo   = signal<PlazoResult | null>(null);
  agregandoPlazo   = signal(false);

  tipos   = ['civil','penal','familiar','laboral','comercial','constitucional','otro'];
  estados = ['activo','en_espera','cerrado','archivado'];

  colores: Record<string, string> = {
    civil:'#1a5296', penal:'#c0392b', familiar:'#1a6b3c',
    laboral:'#c4922a', comercial:'#6c3483', constitucional:'#2e86ab', otro:'#7a7268'
  };

  readonly plazosTipos: Record<string, string> = {
    'apelacion_civil':      'Apelación Civil (10 días)',
    'apelacion_penal':      'Apelación Penal (5 días)',
    'contestacion_demanda': 'Contestación de Demanda (30 días)',
    'casacion':             'Recurso de Casación (10 días)',
    'excepcion_previa':     'Excepción Previa (15 días)',
    'recurso_reposicion':   'Recurso de Reposición (3 días)',
  };

  constructor(
    private svc: CasesService,
    private calSvc: CalendarService,
    private router: Router,
    private fb: FormBuilder
  ) {
    this.form = this.fb.group({
      titulo:            ['', Validators.required],
      cliente:           ['', Validators.required],
      tipo:              ['civil', Validators.required],
      estado:            ['activo'],
      descripcion:       [''],
      numero_expediente: [''],
      juzgado:           [''],
      contraparte:       [''],
      fecha_inicio:      [new Date().toISOString().split('T')[0]]
    });

    this.plazoForm = this.fb.group({
      tipo_plazo:   ['contestacion_demanda', Validators.required],
      fecha_inicio: [new Date().toISOString().split('T')[0], Validators.required]
    });
  }

  ngOnInit() { this.cargar(); }

  cargar() {
    this.cargando.set(true);
    this.svc.list({ estado: this.filtroEstado, tipo: this.filtroTipo, q: this.busqueda })
      .subscribe({
        next: r => { this.casos.set(r.casos || []); this.cargando.set(false); },
        error: () => this.cargando.set(false)
      });
  }

  abrirDetalle(caso: Caso) {
    this.cargando.set(true);
    this.svc.get(caso.id!).subscribe(r => {
      this.casoSeleccionado.set(r);
      this.vista.set('detalle');
      this.cargando.set(false);
      this.resultadoPlazo.set(null);
    });
  }

  guardar() {
    if (this.form.invalid) return;
    this.cargando.set(true);
    this.svc.create(this.form.value).subscribe({
      next: () => { this.form.reset(); this.cargar(); this.vista.set('lista'); },
      error: () => this.cargando.set(false)
    });
  }

  cambiarEstado(id: string, estado: string) {
    this.svc.update(id, { estado }).subscribe(() => this.cargar());
  }

  agregarNota() {
    if (!this.nuevaNota.trim()) return;
    const c = this.casoSeleccionado();
    this.svc.addNote(c.caso.id, this.nuevaNota).subscribe(r => {
      const actual = this.casoSeleccionado();
      actual.notas = [r.nota, ...(actual.notas || [])];
      this.casoSeleccionado.set({...actual});
      this.nuevaNota = '';
    });
  }

  eliminar(id: string) {
    if (!confirm('¿Eliminar este caso?')) return;
    this.svc.delete(id).subscribe(() => this.cargar());
  }

  // ── PLAZOS ───────────────────────────────────────────────

  calcularPlazo() {
    if (this.plazoForm.invalid) return;
    const v = this.plazoForm.value;
    const casoId = this.casoSeleccionado()?.caso?.id;
    this.calSvc.calcularPlazo(v.tipo_plazo, v.fecha_inicio, casoId)
      .subscribe(r => this.resultadoPlazo.set(r));
  }

  agregarAlCalendario() {
    const r = this.resultadoPlazo();
    if (!r) return;
    this.agregandoPlazo.set(true);
    this.calSvc.create(r.evento_sugerido).subscribe({
      next: () => {
        this.agregandoPlazo.set(false);
        this.resultadoPlazo.set(null);
      },
      error: () => this.agregandoPlazo.set(false)
    });
  }

  // ── GENERAR BORRADOR DESDE CASO ──────────────────────────

  generarBorrador(tipoPlazo: string) {
    const caso = this.casoSeleccionado()?.caso;
    if (!caso) return;

    const tipoDoc = this.mapTipoPlazToDoc(tipoPlazo);
    const params = new URLSearchParams({
      tipo: tipoDoc,
      cliente: caso.cliente,
      expediente: caso.numero_expediente || '',
      juzgado: caso.juzgado || '',
      contraparte: caso.contraparte || '',
      tipo_caso: caso.tipo
    });

    this.router.navigate(['/documents'], { queryParams: { prefill: params.toString() } });
  }

  mapTipoPlazToDoc(tipo: string): string {
    const map: Record<string, string> = {
      'apelacion_civil':      'memorial',
      'apelacion_penal':      'memorial',
      'contestacion_demanda': 'demanda-civil',
      'casacion':             'memorial',
      'excepcion_previa':     'memorial',
      'recurso_reposicion':   'memorial',
    };
    return map[tipo] || 'memorial';
  }

  getDiasQuedan(): number { return this.resultadoPlazo()?.dias_quedan ?? 0; }
  getDiasClass(): string {
    const d = this.getDiasQuedan();
    if (d <= 3) return 'urgente';
    if (d <= 7) return 'proximo';
    return 'normal';
  }

  get casosFiltrados(): Caso[] {
    if (!this.busqueda) return this.casos();
    const q = this.busqueda.toLowerCase();
    return this.casos().filter(c =>
      c.titulo.toLowerCase().includes(q) || c.cliente.toLowerCase().includes(q));
  }

  colorTipo(t: string) { return this.colores[t] || '#7a7268'; }

  badgeEstado(e: string) {
    const m: Record<string, string> = {
      activo:'badge-activo', en_espera:'badge-espera',
      cerrado:'badge-cerrado', archivado:'badge-archivado'
    };
    return m[e] || 'badge-cerrado';
  }

  get plazosList() { return Object.keys(this.plazosTipos); }
  getPlazosLabel(k: string) { return this.plazosTipos[k] || k; }
}
