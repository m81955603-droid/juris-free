import { Component, OnInit, signal, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

interface UsuarioPerfil {
  id: string;
  email: string;
  nombre: string;
  rol: 'admin' | 'abogado';
  estado: 'pendiente' | 'aprobado' | 'rechazado';
  fecha_registro: string;
  fecha_aprobacion: string | null;
}

@Component({
  selector: 'app-admin',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './admin.component.html',
  styleUrls: ['./admin.component.scss']
})
export class AdminComponent implements OnInit {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl + '/api/v1/admin';

  usuarios = signal<UsuarioPerfil[]>([]);
  cargando = signal(true);
  errorMsg = signal<string | null>(null);
  procesando = signal<string | null>(null); // id del usuario en proceso
  filtro = signal<'todos' | 'pendiente' | 'aprobado' | 'rechazado'>('pendiente');

  usuariosFiltrados = computed(() => {
    const f = this.filtro();
    const lista = this.usuarios();
    return f === 'todos' ? lista : lista.filter(u => u.estado === f);
  });

  pendientesCount = computed(() => this.usuarios().filter(u => u.estado === 'pendiente').length);

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando.set(true);
    this.errorMsg.set(null);
    this.http.get<UsuarioPerfil[]>(`${this.apiUrl}/usuarios`).subscribe({
      next: (data) => {
        this.usuarios.set(data);
        this.cargando.set(false);
      },
      error: () => {
        this.errorMsg.set('No se pudo cargar la lista de usuarios.');
        this.cargando.set(false);
      }
    });
  }

  setFiltro(f: 'todos' | 'pendiente' | 'aprobado' | 'rechazado') {
    this.filtro.set(f);
  }

  aprobar(usuario: UsuarioPerfil) {
    this.procesando.set(usuario.id);
    this.http.post(`${this.apiUrl}/usuarios/${usuario.id}/aprobar`, {}).subscribe({
      next: () => { this.cargar(); this.procesando.set(null); },
      error: () => { this.errorMsg.set('No se pudo aprobar al usuario.'); this.procesando.set(null); }
    });
  }

  rechazar(usuario: UsuarioPerfil) {
    this.procesando.set(usuario.id);
    this.http.post(`${this.apiUrl}/usuarios/${usuario.id}/rechazar`, {}).subscribe({
      next: () => { this.cargar(); this.procesando.set(null); },
      error: () => { this.errorMsg.set('No se pudo rechazar al usuario.'); this.procesando.set(null); }
    });
  }

  hacerAdmin(usuario: UsuarioPerfil) {
    if (!confirm(`¿Convertir a ${usuario.email} en administrador? Podrá aprobar/rechazar otras cuentas.`)) return;
    this.procesando.set(usuario.id);
    this.http.post(`${this.apiUrl}/usuarios/${usuario.id}/hacer-admin`, {}).subscribe({
      next: () => { this.cargar(); this.procesando.set(null); },
      error: () => { this.errorMsg.set('No se pudo actualizar el rol.'); this.procesando.set(null); }
    });
  }

  formatearFecha(iso: string): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-BO', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
}
