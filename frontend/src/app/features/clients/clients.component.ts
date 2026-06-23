import { Component, signal, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '../../../environments/environment';

interface Cliente {
  id?: string;
  nombre: string;
  ci_nit?: string;
  telefono?: string;
  email?: string;
  direccion?: string;
  ciudad?: string;
  tipo?: string;
  notas?: string;
  created_at?: string;
}

interface CasoResumen {
  id: string;
  titulo: string;
  tipo: string;
  estado: string;
  fecha_inicio: string;
  numero_expediente?: string;
}

@Component({
  selector: 'app-clients',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './clients.component.html',
  styleUrls: ['./clients.component.scss']
})
export class ClientsComponent implements OnInit {
  private http   = inject(HttpClient);
  private router = inject(Router);
  private api    = environment.apiUrl + '/api/v1';

  clientes       = signal<Cliente[]>([]);
  clienteDetalle = signal<{ cliente: Cliente; casos: CasoResumen[] } | null>(null);
  cargando       = signal(false);
  showForm       = signal(false);
  editando       = signal(false);
  searchTerm     = '';
  vista          = signal<'lista' | 'detalle'>('lista');

  form: Cliente = { nombre: '', tipo: 'persona_natural', ciudad: 'La Paz' };

  readonly coloresTipo: Record<string, string> = {
    civil: '#1a5296', penal: '#c0392b', familiar: '#1a6b3c',
    laboral: '#c4922a', comercial: '#6c3483', constitucional: '#2e86ab', otro: '#7a7268'
  };

  ngOnInit() { this.cargarClientes(); }

  cargarClientes() {
    this.cargando.set(true);
    const url = this.searchTerm.trim()
      ? `${this.api}/clientes?q=${encodeURIComponent(this.searchTerm)}`
      : `${this.api}/clientes`;
    this.http.get<Cliente[]>(url).subscribe({
      next: data => { this.clientes.set(data); this.cargando.set(false); },
      error: () => this.cargando.set(false)
    });
  }

  abrirDetalle(cliente: Cliente) {
    this.cargando.set(true);
    this.http.get<{ cliente: Cliente; casos: CasoResumen[] }>(
      `${this.api}/clientes/${cliente.id}`
    ).subscribe({
      next: data => {
        this.clienteDetalle.set(data);
        this.vista.set('detalle');
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false)
    });
  }

  guardar() {
    if (!this.form.nombre) return;
    const req = this.editando()
      ? this.http.patch(`${this.api}/clientes/${this.form.id}`, this.form)
      : this.http.post(`${this.api}/clientes`, this.form);
    req.subscribe({
      next: () => { this.cancelar(); this.cargarClientes(); },
      error: () => {}
    });
  }

  editar(c: Cliente) {
    this.form = { ...c };
    this.editando.set(true);
    this.showForm.set(true);
  }

  eliminar(id: string) {
    if (!confirm('¿Eliminar este cliente?')) return;
    this.http.delete(`${this.api}/clientes/${id}`).subscribe(() => {
      this.cargarClientes();
      if (this.vista() === 'detalle') this.vista.set('lista');
    });
  }

  cancelar() {
    this.form = { nombre: '', tipo: 'persona_natural', ciudad: 'La Paz' };
    this.editando.set(false);
    this.showForm.set(false);
  }

  irACaso(casoId: string) {
    this.router.navigate(['/cases'], { queryParams: { id: casoId } });
  }

  getIniciales(nombre: string): string {
    return nombre.split(' ').slice(0, 2).map(n => n[0]).join('').toUpperCase();
  }

  getColorTipo(tipo: string): string {
    return this.coloresTipo[tipo] || '#7a7268';
  }

  getBadgeEstado(estado: string): string {
    const m: Record<string, string> = {
      activo: 'badge-activo', en_espera: 'badge-espera',
      cerrado: 'badge-cerrado', archivado: 'badge-archivado'
    };
    return m[estado] || 'badge-cerrado';
  }

  buscar() { this.cargarClientes(); }
  volver() { this.vista.set('lista'); this.clienteDetalle.set(null); }
}
