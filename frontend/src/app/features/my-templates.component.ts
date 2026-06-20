import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-my-templates',
  standalone: true,
  imports: [CommonModule],
  template: `
<div class="mt-wrap">
  <header class="mt-header">
    <div>
      <h1 class="mt-title">Mis Plantillas</h1>
      <p class="mt-sub">Documentos con tu estilo personal de redacción</p>
    </div>
  </header>
  <div class="mt-body">
    <div class="mt-empty">
      <div class="mt-empty-icon">📋</div>
      <h2>Construye tu biblioteca personal</h2>
      <p>Sube documentos Word que ya redactaste y la IA aprende tu estilo.<br>
         Cada nuevo documento que generes adoptará tu forma de escribir.</p>
      <div class="mt-features">
        <div class="mt-feat">
          <span class="mt-feat-icon">🔍</span>
          <div>
            <strong>Análisis de estilo</strong>
            <p>Detecta tu tono, estructura y terminología preferida</p>
          </div>
        </div>
        <div class="mt-feat">
          <span class="mt-feat-icon">✨</span>
          <div>
            <strong>Variables inteligentes</strong>
            <p>Identifica los campos que cambian en cada documento</p>
          </div>
        </div>
        <div class="mt-feat">
          <span class="mt-feat-icon">⚡</span>
          <div>
            <strong>Generación personalizada</strong>
            <p>Nuevos documentos con tu misma firma jurídica</p>
          </div>
        </div>
      </div>
      <div class="mt-coming">
        <span class="mt-coming-badge">Próximamente</span>
        <p>Módulo en desarrollo — disponible en la siguiente versión</p>
      </div>
    </div>
  </div>
</div>
  `,
  styles: [`
    .mt-wrap { display: flex; flex-direction: column; height: 100vh; overflow: hidden; background: var(--bg); }
    .mt-header { padding: 16px 28px; background: var(--surf); border-bottom: 1px solid var(--bord); flex-shrink: 0; }
    .mt-title { font-family: 'Playfair Display', serif; font-size: 1.1rem; font-weight: 600; color: var(--txt); margin: 0; }
    .mt-sub { font-size: .72rem; color: var(--txt-3); margin-top: 2px; }
    .mt-body { flex: 1; overflow-y: auto; display: flex; align-items: center; justify-content: center; padding: 32px; }
    .mt-empty { text-align: center; max-width: 520px; }
    .mt-empty-icon { font-size: 3rem; margin-bottom: 16px; }
    .mt-empty h2 { font-family: 'Playfair Display', serif; font-size: 1.1rem; color: var(--txt); margin-bottom: 12px; }
    .mt-empty > p { font-size: .85rem; color: var(--txt-3); line-height: 1.6; margin-bottom: 28px; }
    .mt-features { display: flex; flex-direction: column; gap: 12px; text-align: left; margin-bottom: 28px; }
    .mt-feat { display: flex; gap: 14px; align-items: flex-start; background: var(--surf); border: 1px solid var(--bord); border-radius: 10px; padding: 14px 16px; }
    .mt-feat-icon { font-size: 1.3rem; flex-shrink: 0; }
    .mt-feat strong { font-size: .85rem; font-weight: 500; color: var(--txt); display: block; margin-bottom: 2px; }
    .mt-feat p { font-size: .76rem; color: var(--txt-3); margin: 0; }
    .mt-coming { background: var(--gold-bg); border: 1px solid rgba(184,135,42,.2); border-radius: 10px; padding: 14px 18px; }
    .mt-coming-badge { display: inline-block; background: var(--gold); color: white; font-size: .68rem; font-weight: 600; padding: 2px 8px; border-radius: 10px; margin-bottom: 6px; letter-spacing: .04em; }
    .mt-coming p { font-size: .78rem; color: var(--gold); margin: 0; }
  `]
})
export class MyTemplatesComponent {}
