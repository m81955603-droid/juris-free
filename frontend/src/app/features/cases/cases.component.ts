import { Component, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule, ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { CasesService, Caso } from '../../core/services/cases.service';

@Component({
  selector: 'app-cases',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule],
  templateUrl: './cases.component.html',
  styleUrls: ['./cases.component.scss']
})
export class CasesComponent implements OnInit {
  casos = signal<Caso[]>([]);
  casoSeleccionado = signal<any>(null);
  vista = signal<'lista'|'detalle'|'nuevo'>('lista');
  cargando = signal(false);
  busqueda = '';
  filtroEstado = '';
  filtroTipo = '';
  nuevaNota = '';
  form: FormGroup;

  tipos   = ['civil','penal','familiar','laboral','comercial','constitucional','otro'];
  estados = ['activo','en_espera','cerrado','archivado'];
  colores: Record<string,string> = {
    civil:'#2563eb', penal:'#dc2626', familiar:'#16a34a',
    laboral:'#d97706', comercial:'#7c3aed', constitucional:'#0891b2', otro:'#6b7280'
  };

  constructor(private svc: CasesService, private fb: FormBuilder) {
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

  get casosFiltrados(): Caso[] {
    if (!this.busqueda) return this.casos();
    const q = this.busqueda.toLowerCase();
    return this.casos().filter(c =>
      c.titulo.toLowerCase().includes(q) || c.cliente.toLowerCase().includes(q));
  }

  colorTipo(t: string) { return this.colores[t] || '#6b7280'; }
  badgeEstado(e: string) {
    const m: Record<string,string> = {
      activo:'badge-activo', en_espera:'badge-espera',
      cerrado:'badge-cerrado', archivado:'badge-archivado'
    };
    return m[e] || 'badge-cerrado';
  }
}
