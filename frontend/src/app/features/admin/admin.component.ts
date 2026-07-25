import { Component, OnInit, signal, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
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
  imports: [CommonModule, FormsModule],
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

  // ── Formulario de creacion directa ──
  mostrarFormCrear = signal(false);
  creandoUsuario = signal(false);
  errorCrear = signal<string | null>(null);
  exitoCrear = signal<string | null>(null);
  nuevoEmail = '';
  nuevoPassword = '';
  nuevoNombre = '';
  nuevoAprobarDeInmediato = true;

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

  suspender(usuario: UsuarioPerfil) {
    // Misma accion en el backend que "rechazar" (marca estado='rechazado'),
    // pero aqui pedimos confirmacion porque corta el acceso a alguien que
    // YA estaba usando el sistema activamente, a diferencia de rechazar
    // una solicitud nueva que nunca tuvo acceso.
    const confirmado = confirm(
      `¿Seguro que quieres suspender a ${usuario.nombre || usuario.email}? Perderá el acceso al sistema de inmediato.`
    );
    if (!confirmado) return;
    this.rechazar(usuario);
  }

  formatearFecha(iso: string): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-BO', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  // ── Creacion directa de usuarios ──

  abrirFormCrear() {
    this.mostrarFormCrear.set(true);
    this.errorCrear.set(null);
    this.exitoCrear.set(null);
    this.nuevoEmail = '';
    this.nuevoPassword = '';
    this.nuevoNombre = '';
    this.nuevoAprobarDeInmediato = true;
  }

  cerrarFormCrear() {
    this.mostrarFormCrear.set(false);
  }

  crearUsuario() {
    this.errorCrear.set(null);
    this.exitoCrear.set(null);

    if (!this.nuevoEmail.trim() || !this.nuevoPassword.trim()) {
      this.errorCrear.set('Completa el email y la contraseña.');
      return;
    }
    if (this.nuevoPassword.length < 6) {
      this.errorCrear.set('La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    this.creandoUsuario.set(true);
    this.http.post(`${this.apiUrl}/usuarios/crear`, {
      email: this.nuevoEmail.trim(),
      password: this.nuevoPassword,
      nombre: this.nuevoNombre.trim(),
      aprobar_de_inmediato: this.nuevoAprobarDeInmediato
    }).subscribe({
      next: () => {
        this.exitoCrear.set(`Cuenta creada: ${this.nuevoEmail}`);
        this.creandoUsuario.set(false);
        this.nuevoEmail = '';
        this.nuevoPassword = '';
        this.nuevoNombre = '';
        this.cargar();
      },
      error: (err: HttpErrorResponse) => {
        this.errorCrear.set(err.error?.detail || 'No se pudo crear la cuenta.');
        this.creandoUsuario.set(false);
      }
    });
  }
}
