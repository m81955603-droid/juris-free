import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-settings',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:80vh;gap:16px;color:#7a6e5e;font-family:Georgia,serif">
      <h2 style="color:#1a3a5c">Configuracion</h2>
      <p>Preferencias, API keys y estadisticas de uso</p>
      <p style="font-size:.8rem;background:#f0ede8;padding:8px 16px;border-radius:8px">Proximo modulo - en desarrollo</p>
    </div>
  `
})
export class SettingsComponent {}