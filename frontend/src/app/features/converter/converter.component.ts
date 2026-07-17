import { Component, signal, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

type Direccion = 'word-to-pdf' | 'pdf-to-word';

interface ArchivoConvertido {
  nombre: string;
  blob: Blob;
  url: string;
}

@Component({
  selector: 'app-converter',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './converter.component.html',
  styleUrls: ['./converter.component.scss']
})
export class ConverterComponent {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl + '/api/v1/convert';

  direccion = signal<Direccion>('word-to-pdf');
  archivoSeleccionado = signal<File | null>(null);
  convirtiendo = signal(false);
  errorMsg = signal<string | null>(null);
  resultado = signal<ArchivoConvertido | null>(null);
  arrastrando = signal(false);

  setDireccion(d: Direccion) {
    this.direccion.set(d);
    this.limpiar();
  }

  get extensionEsperada(): string {
    return this.direccion() === 'word-to-pdf' ? '.docx' : '.pdf';
  }

  get etiquetaOrigen(): string {
    return this.direccion() === 'word-to-pdf' ? 'Word (.docx)' : 'PDF (.pdf)';
  }

  get etiquetaDestino(): string {
    return this.direccion() === 'word-to-pdf' ? 'PDF' : 'Word editable (.docx)';
  }

  onFileSelected(ev: Event) {
    const input = ev.target as HTMLInputElement;
    if (input.files && input.files[0]) {
      this.procesarArchivoSeleccionado(input.files[0]);
    }
  }

  onDrop(ev: DragEvent) {
    ev.preventDefault();
    this.arrastrando.set(false);
    const file = ev.dataTransfer?.files?.[0];
    if (file) this.procesarArchivoSeleccionado(file);
  }

  onDragOver(ev: DragEvent) {
    ev.preventDefault();
    this.arrastrando.set(true);
  }

  onDragLeave() {
    this.arrastrando.set(false);
  }

  private procesarArchivoSeleccionado(file: File) {
    this.errorMsg.set(null);
    this.resultado.set(null);

    const ext = this.extensionEsperada;
    if (!file.name.toLowerCase().endsWith(ext)) {
      this.errorMsg.set(`Este convertidor solo acepta archivos ${ext}`);
      return;
    }
    if (file.size > 25 * 1024 * 1024) {
      this.errorMsg.set('El archivo supera el límite de 25 MB');
      return;
    }
    this.archivoSeleccionado.set(file);
  }

  convertir() {
    const file = this.archivoSeleccionado();
    if (!file) return;

    this.convirtiendo.set(true);
    this.errorMsg.set(null);
    this.resultado.set(null);

    const endpoint = this.direccion() === 'word-to-pdf' ? 'word-to-pdf' : 'pdf-to-word';
    const formData = new FormData();
    formData.append('file', file);

    this.http.post(`${this.apiUrl}/${endpoint}`, formData, { responseType: 'blob' }).subscribe({
      next: (blob) => {
        const nombreBase = file.name.replace(/\.(docx|pdf)$/i, '');
        const nombreSalida = this.direccion() === 'word-to-pdf'
          ? `${nombreBase}.pdf`
          : `${nombreBase}.docx`;
        const url = URL.createObjectURL(blob);
        this.resultado.set({ nombre: nombreSalida, blob, url });
        this.convirtiendo.set(false);
      },
      error: (err) => {
        this.errorMsg.set('No se pudo convertir el archivo. Verifica que no esté dañado o protegido con contraseña.');
        this.convirtiendo.set(false);
      }
    });
  }

  descargarResultado() {
    const r = this.resultado();
    if (!r) return;
    const link = document.createElement('a');
    link.href = r.url;
    link.download = r.nombre;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }

  limpiar() {
    const r = this.resultado();
    if (r) URL.revokeObjectURL(r.url);
    this.archivoSeleccionado.set(null);
    this.resultado.set(null);
    this.errorMsg.set(null);
  }
}
