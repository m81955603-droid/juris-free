import { Component, OnInit, signal, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

interface UsuarioPerfil {
  id: string;
  email: string;
  nombre: string;
  rol: 'admin' | 'abogado';
  estado: 'pendiente' | 'aprobado' | 'rechazado';
}

interface ProveedorInfo {
  campo: string;
  nombre: string;
  descripcion: string;
  urlObtener: string;
}

@Component({
  selector: 'app-settings',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './settings.component.html',
  styleUrls: ['./settings.component.scss']
})
export class SettingsComponent implements OnInit {
  private http = inject(HttpClient);
  private adminUrl = environment.apiUrl + '/api/v1/admin';

  cargandoUsuarios = signal(true);
  cargandoClaves = signal(false);
  guardando = signal(false);
  errorMsg = signal<string | null>(null);
  exitoMsg = signal<string | null>(null);

  usuarios = signal<UsuarioPerfil[]>([]);
  usuarioSeleccionado = signal<UsuarioPerfil | null>(null);
  valores: Record<string, string> = {};

  readonly proveedores: ProveedorInfo[] = [
    { campo: 'gemini_api_key',     nombre: 'Google Gemini', descripcion: 'Usado en Consulta IA, Generador y Scanner', urlObtener: 'https://aistudio.google.com/app/apikey' },
    { campo: 'groq_api_key',       nombre: 'Groq',          descripcion: 'Respaldo rapido para Consulta IA y Scanner', urlObtener: 'https://console.groq.com/keys' },
    { campo: 'cerebras_api_key',   nombre: 'Cerebras',      descripcion: 'Respaldo para Consulta IA',                  urlObtener: 'https://cloud.cerebras.ai' },
    { campo: 'openrouter_api_key', nombre: 'OpenRouter',    descripcion: 'Respaldo para Consulta IA',                  urlObtener: 'https://openrouter.ai/keys' },
    { campo: 'sambanova_api_key',  nombre: 'SambaNova',     descripcion: 'Respaldo para Consulta IA',                  urlObtener: 'https://cloud.sambanova.ai/apis' },
    { campo: 'mistral_api_key',    nombre: 'Mistral',       descripcion: 'Respaldo especializado para el Scanner',     urlObtener: 'https://console.mistral.ai' },
  ];

  usuariosOrdenados = computed(() =>
    [...this.usuarios()].sort((a, b) => (a.nombre || a.email).localeCompare(b.nombre || b.email))
  );

  ngOnInit() {
    this.cargarUsuarios();
  }

  cargarUsuarios() {
    this.cargandoUsuarios.set(true);
    this.http.get<UsuarioPerfil[]>(`${this.adminUrl}/usuarios`).subscribe({
      next: (data) => {
        this.usuarios.set(data.filter(u => u.estado !== 'rechazado'));
        this.cargandoUsuarios.set(false);
      },
      error: () => {
        this.errorMsg.set('No se pudo cargar la lista de abogados.');
        this.cargandoUsuarios.set(false);
      }
    });
  }

  seleccionar(u: UsuarioPerfil) {
    this.usuarioSeleccionado.set(u);
    this.errorMsg.set(null);
    this.exitoMsg.set(null);
    this.valores = {};
    this.cargandoClaves.set(true);

    this.http.get<Record<string, string>>(`${this.adminUrl}/usuarios/${u.id}/api-keys`).subscribe({
      next: (data) => {
        this.valores = { ...data };
        this.cargandoClaves.set(false);
      },
      error: () => {
        this.errorMsg.set('No se pudieron cargar las claves de este abogado.');
        this.cargandoClaves.set(false);
      }
    });
  }

  volver() {
    this.usuarioSeleccionado.set(null);
  }

  guardarClaves() {
    const u = this.usuarioSeleccionado();
    if (!u) return;

    this.guardando.set(true);
    this.errorMsg.set(null);
    this.exitoMsg.set(null);

    const body: Record<string, string> = {};
    for (const p of this.proveedores) {
      body[p.campo] = this.valores[p.campo] || '';
    }

    this.http.post(`${this.adminUrl}/usuarios/${u.id}/api-keys`, body).subscribe({
      next: () => {
        this.exitoMsg.set(`Claves de ${u.nombre || u.email} actualizadas`);
        this.guardando.set(false);
        setTimeout(() => this.exitoMsg.set(null), 3000);
      },
      error: () => {
        this.errorMsg.set('No se pudieron guardar las claves.');
        this.guardando.set(false);
      }
    });
  }
}
