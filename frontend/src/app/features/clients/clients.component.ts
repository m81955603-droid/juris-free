import { Component, signal, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpClientModule } from '@angular/common/http';
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
}

@Component({
  selector: 'app-clients',
  standalone: true,
  imports: [CommonModule, FormsModule, HttpClientModule],
  template: `
<div class="clients-container">
  <div class="clients-header">
    <h1>👥 Directorio de Clientes</h1>
    <button class="btn-primary" (click)="showForm.set(true)">+ Nuevo Cliente</button>
  </div>

  <div class="search-bar">
    <input type="text" placeholder="Buscar cliente..." [(ngModel)]="searchTerm" (input)="buscar()" />
  </div>

  <div class="form-modal" *ngIf="showForm()">
    <div class="form-card">
      <h2>{{ editando() ? 'Editar' : 'Nuevo' }} Cliente</h2>
      <div class="form-grid">
        <input placeholder="Nombre completo *" [(ngModel)]="form.nombre" />
        <input placeholder="CI / NIT" [(ngModel)]="form.ci_nit" />
        <input placeholder="Teléfono" [(ngModel)]="form.telefono" />
        <input placeholder="Email" [(ngModel)]="form.email" />
        <input placeholder="Dirección" [(ngModel)]="form.direccion" />
        <input placeholder="Ciudad" [(ngModel)]="form.ciudad" />
        <select [(ngModel)]="form.tipo">
          <option value="persona_natural">Persona Natural</option>
          <option value="empresa">Empresa</option>
        </select>
        <textarea placeholder="Notas adicionales" [(ngModel)]="form.notas"></textarea>
      </div>
      <div class="form-actions">
        <button class="btn-secondary" (click)="cancelar()">Cancelar</button>
        <button class="btn-primary" (click)="guardar()">Guardar</button>
      </div>
    </div>
  </div>

  <div class="clientes-grid" *ngIf="!cargando()">
    <div class="cliente-card" *ngFor="let c of clientes()">
      <div class="cliente-header">
        <span class="cliente-avatar">{{ c.nombre[0] }}</span>
        <div>
          <h3>{{ c.nombre }}</h3>
          <span class="badge">{{ c.tipo === 'empresa' ? '🏢 Empresa' : '👤 Persona' }}</span>
        </div>
      </div>
      <div class="cliente-info">
        <p *ngIf="c.telefono">📞 {{ c.telefono }}</p>
        <p *ngIf="c.email">✉️ {{ c.email }}</p>
        <p *ngIf="c.ci_nit">🪪 {{ c.ci_nit }}</p>
        <p *ngIf="c.ciudad">📍 {{ c.ciudad }}</p>
      </div>
      <div class="cliente-actions">
        <button class="btn-edit" (click)="editar(c)">✏️ Editar</button>
        <button class="btn-delete" (click)="eliminar(c.id!)">🗑️ Eliminar</button>
      </div>
    </div>
    <div class="empty-state" *ngIf="clientes().length === 0">
      <p>No hay clientes registrados. ¡Agrega el primero!</p>
    </div>
  </div>
  <div *ngIf="cargando()" class="loading">Cargando clientes...</div>
</div>
  `,
  styleUrls: ['./clients.component.scss']
    .clients-container { padding: 2rem; max-width: 1200px; margin: 0 auto; }
    .clients-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem; }
    .clients-header h1 { font-size: 1.8rem; font-weight: 700; }
    .search-bar input { width: 100%; padding: 0.75rem 1rem; border: 1px solid #e2e8f0; border-radius: 8px; font-size: 1rem; margin-bottom: 1.5rem; }
    .clientes-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
    .cliente-card { background: white; border-radius: 12px; padding: 1.25rem; box-shadow: 0 2px 8px rgba(0,0,0,0.08); border: 1px solid #e2e8f0; }
    .cliente-header { display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem; }
    .cliente-avatar { width: 48px; height: 48px; border-radius: 50%; background: linear-gradient(135deg, #667eea, #764ba2); color: white; display: flex; align-items: center; justify-content: center; font-size: 1.4rem; font-weight: 700; flex-shrink: 0; }
    .cliente-header h3 { font-size: 1rem; font-weight: 600; margin: 0; }
    .badge { font-size: 0.75rem; color: #64748b; }
    .cliente-info p { font-size: 0.875rem; color: #64748b; margin: 0.25rem 0; }
    .cliente-actions { display: flex; gap: 0.5rem; margin-top: 1rem; }
    .btn-primary { background: linear-gradient(135deg, #667eea, #764ba2); color: white; border: none; padding: 0.6rem 1.25rem; border-radius: 8px; cursor: pointer; font-weight: 600; }
    .btn-secondary { background: #f1f5f9; color: #475569; border: none; padding: 0.6rem 1.25rem; border-radius: 8px; cursor: pointer; }
    .btn-edit { background: #eff6ff; color: #3b82f6; border: none; padding: 0.4rem 0.75rem; border-radius: 6px; cursor: pointer; font-size: 0.8rem; }
    .btn-delete { background: #fef2f2; color: #ef4444; border: none; padding: 0.4rem 0.75rem; border-radius: 6px; cursor: pointer; font-size: 0.8rem; }
    .form-modal { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 1000; }
    .form-card { background: white; border-radius: 16px; padding: 2rem; width: 90%; max-width: 500px; }
    .form-card h2 { margin-bottom: 1.5rem; font-size: 1.25rem; font-weight: 700; }
    .form-grid { display: grid; gap: 0.75rem; }
    .form-grid input, .form-grid select, .form-grid textarea { padding: 0.75rem; border: 1px solid #e2e8f0; border-radius: 8px; font-size: 0.9rem; width: 100%; box-sizing: border-box; }
    .form-grid textarea { height: 80px; resize: vertical; }
    .form-actions { display: flex; gap: 0.75rem; margin-top: 1.5rem; justify-content: flex-end; }
    .empty-state { grid-column: 1/-1; text-align: center; padding: 3rem; color: #94a3b8; }
    .loading { text-align: center; padding: 2rem; color: #94a3b8; }
  `]
})
export class ClientsComponent implements OnInit {
  private http = inject(HttpClient);
  private api = environment.apiUrl + '/api/v1';

  clientes  = signal<Cliente[]>([]);
  cargando  = signal(false);
  showForm  = signal(false);
  editando  = signal(false);
  searchTerm = '';

  form: Cliente = { nombre: '', tipo: 'persona_natural', ciudad: 'La Paz' };

  ngOnInit() { this.cargarClientes(); }

  cargarClientes() {
    this.cargando.set(true);
    this.http.get<Cliente[]>(this.api + '/clientes').subscribe({
      next: data => { this.clientes.set(data); this.cargando.set(false); },
      error: () => { this.cargando.set(false); }
    });
  }

  buscar() {
    const q = this.searchTerm.trim();
    const url = q ? this.api + '/clientes?q=' + q : this.api + '/clientes';
    this.http.get<Cliente[]>(url).subscribe(data => this.clientes.set(data));
  }

  guardar() {
    if (!this.form.nombre) return;
    const req = this.editando()
      ? this.http.patch(this.api + '/clientes/' + this.form.id, this.form)
      : this.http.post(this.api + '/clientes', this.form);
    req.subscribe({ next: () => { this.cancelar(); this.cargarClientes(); }, error: () => {} });
  }

  editar(c: Cliente) { this.form = { ...c }; this.editando.set(true); this.showForm.set(true); }

  eliminar(id: string) {
    if (!confirm('¿Eliminar este cliente?')) return;
    this.http.delete(this.api + '/clientes/' + id).subscribe(() => this.cargarClientes());
  }

  cancelar() { this.form = { nombre: '', tipo: 'persona_natural', ciudad: 'La Paz' }; this.editando.set(false); this.showForm.set(false); }
}
