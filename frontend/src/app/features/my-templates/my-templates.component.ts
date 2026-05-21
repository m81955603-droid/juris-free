import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-my-templates',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:80vh;gap:16px;font-family:Georgia,serif;color:#7a6e5e">
      <div style="font-size:3rem">📋</div>
      <h2 style="color:#1a3a5c">Mis Plantillas</h2>
      <p>Sube tus documentos Word y genera nuevos con tu mismo estilo</p>
    </div>
  `
})
export class MyTemplatesComponent {}