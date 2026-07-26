import { Component, OnInit, signal, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

interface ProveedorInfo {
  key: 'gemini' | 'groq' | 'cerebras' | 'openrouter' | 'sambanova' | 'mistral';
  campo: string; // nombre del campo en el POST (ej. gemini_api_key)
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
  private apiUrl = environment.apiUrl + '/api/v1/settings';

  cargando = signal(true);
  guardando = signal<string | null>(null); // key del proveedor en proceso
  errorMsg = signal<string | null>(null);
  exitoMsg = signal<string | null>(null);

  configurado = signal<Record<string, boolean>>({});
  valoresNuevos: Record<string, string> = {};

  readonly proveedores: ProveedorInfo[] = [
    { key: 'gemini',     campo: 'gemini_api_key',     nombre: 'Google Gemini', descripcion: 'Usado en Consulta IA, Generador y Scanner', urlObtener: 'https://aistudio.google.com/app/apikey' },
    { key: 'groq',       campo: 'groq_api_key',       nombre: 'Groq',          descripcion: 'Respaldo rapido para Consulta IA y Scanner', urlObtener: 'https://console.groq.com/keys' },
    { key: 'cerebras',   campo: 'cerebras_api_key',   nombre: 'Cerebras',      descripcion: 'Respaldo para Consulta IA',                  urlObtener: 'https://cloud.cerebras.ai' },
    { key: 'openrouter', campo: 'openrouter_api_key', nombre: 'OpenRouter',    descripcion: 'Respaldo para Consulta IA',                  urlObtener: 'https://openrouter.ai/keys' },
    { key: 'sambanova',  campo: 'sambanova_api_key',  nombre: 'SambaNova',     descripcion: 'Respaldo para Consulta IA',                  urlObtener: 'https://cloud.sambanova.ai/apis' },
    { key: 'mistral',    campo: 'mistral_api_key',    nombre: 'Mistral',      descripcion: 'Respaldo especializado para el Scanner',      urlObtener: 'https://console.mistral.ai' },
  ];

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando.set(true);
    this.http.get<Record<string, boolean>>(`${this.apiUrl}/api-keys`).subscribe({
      next: (data) => {
        this.configurado.set(data);
        this.cargando.set(false);
      },
      error: () => {
        this.errorMsg.set('No se pudo cargar el estado de tus claves.');
        this.cargando.set(false);
      }
    });
  }

  guardar(p: ProveedorInfo) {
    const valor = (this.valoresNuevos[p.key] || '').trim();
    if (!valor) return;

    this.guardando.set(p.key);
    this.errorMsg.set(null);
    this.exitoMsg.set(null);

    this.http.post(`${this.apiUrl}/api-keys`, { [p.campo]: valor }).subscribe({
      next: () => {
        this.exitoMsg.set(`Clave de ${p.nombre} guardada`);
        this.valoresNuevos[p.key] = '';
        this.guardando.set(null);
        this.cargar();
        setTimeout(() => this.exitoMsg.set(null), 3000);
      },
      error: () => {
        this.errorMsg.set(`No se pudo guardar la clave de ${p.nombre}.`);
        this.guardando.set(null);
      }
    });
  }

  borrar(p: ProveedorInfo) {
    if (!confirm(`¿Quitar tu clave personal de ${p.nombre}? Volverás a usar la clave compartida del sistema.`)) return;

    this.guardando.set(p.key);
    this.http.delete(`${this.apiUrl}/api-keys/${p.key}`).subscribe({
      next: () => {
        this.exitoMsg.set(`Clave de ${p.nombre} eliminada`);
        this.guardando.set(null);
        this.cargar();
        setTimeout(() => this.exitoMsg.set(null), 3000);
      },
      error: () => {
        this.errorMsg.set(`No se pudo eliminar la clave de ${p.nombre}.`);
        this.guardando.set(null);
      }
    });
  }
}
