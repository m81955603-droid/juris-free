import { Component, signal, ElementRef, ViewChild, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { environment } from '../../../environments/environment';

type ScanMode = 'idle' | 'camera' | 'processing' | 'result';

interface PaginaEscaneada {
  image: string;      // dataURL (image/jpeg)
  texto: string;       // texto OCR extraido
  proveedor?: string;  // que proveedor de IA lo proceso (informativo)
}

@Component({
  selector: 'app-scanner',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './scanner.component.html',
  styleUrls: ['./scanner.component.scss']
})
export class ScannerComponent {
  private http = inject(HttpClient);
  private router = inject(Router);
  private apiUrl = environment.apiUrl + '/api/v1/ocr';

  @ViewChild('videoEl') videoEl!: ElementRef<HTMLVideoElement>;
  @ViewChild('canvasEl') canvasEl!: ElementRef<HTMLCanvasElement>;
  @ViewChild('signatureCanvas') signatureCanvas?: ElementRef<HTMLCanvasElement>;

  mode = signal<ScanMode>('idle');
  errorMsg = signal<string | null>(null);
  isLoading = signal(false);
  scanType = signal<'document' | 'carnet'>('document');

  // ── Documento: soporta multiples paginas ──────────
  pages = signal<PaginaEscaneada[]>([]);
  currentPageIndex = signal(0);
  currentPage = computed(() => this.pages()[this.currentPageIndex()] ?? null);

  // Para carnet: dos lados (sin cambios, sigue siendo 1 sola tarjeta)
  carnetFront = signal<string | null>(null);
  carnetBack = signal<string | null>(null);
  carnetStep = signal<'front' | 'back'>('front');
  extractedData = signal<any>(null);

  // Acciones (feedback visual)
  copiado = signal(false);
  guardado = signal(false);
  exportando = signal<'pdf' | 'word' | null>(null);
  mejorando = signal(false);

  // Firma digital
  mostrarFirma = signal(false);
  private firmando = false;
  private firmaCtx: CanvasRenderingContext2D | null = null;

  private stream: MediaStream | null = null;

  // ── CAMARA ─────────────────────────────────────────

  async startCamera() {
    this.errorMsg.set(null);
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment', width: { ideal: 1920 }, height: { ideal: 1080 } }
      });
      this.mode.set('camera');
      setTimeout(() => {
        if (this.videoEl) {
          this.videoEl.nativeElement.srcObject = this.stream;
          this.videoEl.nativeElement.play();
        }
      }, 100);
    } catch (e) {
      this.errorMsg.set('No se pudo acceder a la cámara. Verifica los permisos del navegador.');
    }
  }

  capture() {
    const video = this.videoEl.nativeElement;
    const canvas = this.canvasEl.nativeElement;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d')!;
    ctx.drawImage(video, 0, 0);
    const imageData = canvas.toDataURL('image/jpeg', 0.92);
    this.stopStream();

    if (this.scanType() === 'carnet') {
      if (this.carnetStep() === 'front') {
        this.carnetFront.set(imageData);
        this.mode.set('result');
      } else {
        this.carnetBack.set(imageData);
        this.processCarnet();
      }
    } else {
      this.processDocumentPage(imageData);
    }
  }

  /** Vuelve a abrir la camara para escanear una pagina adicional del mismo documento. */
  agregarPagina() {
    this.errorMsg.set(null);
    this.startCamera();
  }

  // ── PROCESAMIENTO OCR (documento, multi-pagina) ────

  private processDocumentPage(imageData: string) {
    this.mode.set('processing');
    this.isLoading.set(true);
    const base64 = imageData.split(',')[1];

    this.http.post<{ text: string; mode: string; proveedor: string }>(`${this.apiUrl}/scan`, {
      image_base64: base64,
      mode: 'document',
      mime_type: 'image/jpeg'
    }).subscribe({
      next: (res) => {
        const nuevaPagina: PaginaEscaneada = {
          image: imageData,
          texto: res?.text?.trim() || '',
          proveedor: res?.proveedor
        };
        this.pages.update(p => [...p, nuevaPagina]);
        this.currentPageIndex.set(this.pages().length - 1);
        this.isLoading.set(false);
        this.mode.set('result');
      },
      error: () => {
        this.errorMsg.set('No se pudo procesar la imagen. Intenta nuevamente con mejor iluminación.');
        this.isLoading.set(false);
        this.mode.set(this.pages().length > 0 ? 'result' : 'idle');
      }
    });
  }

  seleccionarPagina(i: number) {
    this.currentPageIndex.set(i);
  }

  eliminarPagina(i: number) {
    this.pages.update(p => p.filter((_, idx) => idx !== i));
    const total = this.pages().length;
    if (total === 0) {
      this.reset();
      return;
    }
    this.currentPageIndex.set(Math.min(i, total - 1));
  }

  // ── CARNET (sin cambios de fondo) ──────────────────

  private processCarnet() {
    this.mode.set('processing');
    this.isLoading.set(true);
    const backBase64 = this.carnetBack()!.split(',')[1];

    this.http.post<{ text: string }>(`${this.apiUrl}/scan`, {
      image_base64: backBase64,
      mode: 'carnet',
      mime_type: 'image/jpeg'
    }).subscribe({
      next: (res) => {
        const text = res?.text || '{}';
        try {
          const clean = text.replace(/```json|```/g, '').trim();
          this.extractedData.set(JSON.parse(clean));
        } catch {
          this.extractedData.set({ raw: text });
        }
        this.isLoading.set(false);
        this.mode.set('result');
      },
      error: () => {
        this.errorMsg.set('Error al procesar el carnet.');
        this.isLoading.set(false);
        this.mode.set('result');
      }
    });
  }

  captureCarnetBack() {
    this.carnetStep.set('back');
    this.mode.set('idle');
  }

  getCarnetFields() {
    const data = this.extractedData();
    if (!data) return [];
    return [
      { label: 'Nombre Completo', value: data.nombre_completo },
      { label: 'N Carnet', value: data.numero_ci },
      { label: 'Fecha Nacimiento', value: data.fecha_nacimiento },
      { label: 'Lugar Nacimiento', value: data.lugar_nacimiento },
      { label: 'Fecha Expiracion', value: data.fecha_expiracion },
      { label: 'Estado Civil', value: data.estado_civil },
      { label: 'Observaciones', value: data.observaciones },
    ];
  }

  async copyCarnetData() {
    const data = this.extractedData();
    if (data) {
      await this.copiarAlPortapapeles(JSON.stringify(data, null, 2));
    }
  }

  // ── COPIAR / GUARDAR (pagina actual) ───────────────

  async copyText() {
    const text = this.currentPage()?.texto;
    if (!text) return;
    await this.copiarAlPortapapeles(text);
    this.copiado.set(true);
    setTimeout(() => this.copiado.set(false), 2000);
  }

  private async copiarAlPortapapeles(text: string) {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.focus();
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }
  }

  downloadImage() {
    const img = this.currentPage()?.image;
    if (!img) return;
    try {
      const [meta, base64] = img.split(',');
      const mime = meta.match(/:(.*?);/)?.[1] || 'image/jpeg';
      const bytes = atob(base64);
      const arr = new Uint8Array(bytes.length);
      for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
      const blob = new Blob([arr], { type: mime });
      const url = URL.createObjectURL(blob);

      const link = document.createElement('a');
      link.href = url;
      link.download = `escaneado_pagina${this.currentPageIndex() + 1}_${Date.now()}.jpg`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      setTimeout(() => URL.revokeObjectURL(url), 5000);

      this.guardado.set(true);
      setTimeout(() => this.guardado.set(false), 2000);
    } catch {
      this.errorMsg.set('No se pudo guardar la imagen en este navegador.');
    }
  }

  sendToAnalyzer() {
    // Manda el texto combinado de TODAS las paginas al Analizador
    const texto = this.pages().map((p, i) =>
      this.pages().length > 1 ? `--- Página ${i + 1} ---\n${p.texto}` : p.texto
    ).join('\n\n');
    if (!texto.trim()) return;
    sessionStorage.setItem('scanner_ocr_text', texto);
    this.router.navigateByUrl('/analyzer');
  }

  // ── EXPORTAR PDF / WORD (todas las paginas) ────────

  private descargarBlob(blob: Blob, filename: string) {
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  }

  exportarPDF() {
    if (this.pages().length === 0) return;
    this.exportando.set('pdf');
    const body = {
      titulo: 'Documento escaneado',
      paginas: this.pages().map(p => ({
        image_base64: p.image.split(',')[1],
        mime_type: 'image/jpeg',
        texto: p.texto
      }))
    };
    this.http.post(`${this.apiUrl}/export-pdf`, body, { responseType: 'blob' }).subscribe({
      next: (blob) => {
        this.descargarBlob(blob, `documento_${Date.now()}.pdf`);
        this.exportando.set(null);
      },
      error: () => {
        this.errorMsg.set('No se pudo generar el PDF. Intenta nuevamente.');
        this.exportando.set(null);
      }
    });
  }

  exportarWord() {
    if (this.pages().length === 0) return;
    this.exportando.set('word');
    const body = {
      titulo: 'Documento escaneado',
      paginas: this.pages().map(p => ({
        image_base64: p.image.split(',')[1],
        mime_type: 'image/jpeg',
        texto: p.texto
      }))
    };
    this.http.post(`${this.apiUrl}/export-word`, body, { responseType: 'blob' }).subscribe({
      next: (blob) => {
        this.descargarBlob(blob, `documento_${Date.now()}.docx`);
        this.exportando.set(null);
      },
      error: () => {
        this.errorMsg.set('No se pudo generar el documento Word. Intenta nuevamente.');
        this.exportando.set(null);
      }
    });
  }

  // ── MEJORAR IMAGEN (contraste/brillo, en el navegador) ──

  mejorarImagen() {
    const pagina = this.currentPage();
    if (!pagina) return;
    this.mejorando.set(true);

    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext('2d')!;
      // Aumenta contraste y brillo, quita saturacion para look "escaneado"
      (ctx as any).filter = 'contrast(1.35) brightness(1.12) saturate(0.85)';
      ctx.drawImage(img, 0, 0);
      const mejorada = canvas.toDataURL('image/jpeg', 0.92);

      this.pages.update(pages => pages.map((p, i) =>
        i === this.currentPageIndex() ? { ...p, image: mejorada } : p
      ));
      this.mejorando.set(false);
    };
    img.onerror = () => this.mejorando.set(false);
    img.src = pagina.image;
  }

  // ── FIRMA DIGITAL (dibujo simple sobre la pagina) ──

  abrirFirma() {
    if (!this.currentPage()) return;
    this.mostrarFirma.set(true);
    setTimeout(() => this.initSignatureCanvas(), 50);
  }

  cerrarFirma() {
    this.mostrarFirma.set(false);
    this.firmaCtx = null;
  }

  private initSignatureCanvas() {
    const canvas = this.signatureCanvas?.nativeElement;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width;
    canvas.height = rect.height;
    const ctx = canvas.getContext('2d')!;
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#1e293b';
    this.firmaCtx = ctx;
  }

  private posDesdeEvento(canvas: HTMLCanvasElement, ev: PointerEvent) {
    const rect = canvas.getBoundingClientRect();
    return { x: ev.clientX - rect.left, y: ev.clientY - rect.top };
  }

  onFirmaStart(ev: PointerEvent) {
    if (!this.firmaCtx) return;
    this.firmando = true;
    const canvas = this.signatureCanvas!.nativeElement;
    const { x, y } = this.posDesdeEvento(canvas, ev);
    this.firmaCtx.beginPath();
    this.firmaCtx.moveTo(x, y);
  }

  onFirmaMove(ev: PointerEvent) {
    if (!this.firmando || !this.firmaCtx) return;
    const canvas = this.signatureCanvas!.nativeElement;
    const { x, y } = this.posDesdeEvento(canvas, ev);
    this.firmaCtx.lineTo(x, y);
    this.firmaCtx.stroke();
  }

  onFirmaEnd() {
    this.firmando = false;
  }

  limpiarFirma() {
    const canvas = this.signatureCanvas?.nativeElement;
    if (canvas && this.firmaCtx) {
      this.firmaCtx.clearRect(0, 0, canvas.width, canvas.height);
    }
  }

  aplicarFirma() {
    const canvas = this.signatureCanvas?.nativeElement;
    const pagina = this.currentPage();
    if (!canvas || !pagina) return;

    const firmaDataUrl = canvas.toDataURL('image/png');
    const img = new Image();
    img.onload = () => {
      const firmaImg = new Image();
      firmaImg.onload = () => {
        const out = document.createElement('canvas');
        out.width = img.width;
        out.height = img.height;
        const ctx = out.getContext('2d')!;
        ctx.drawImage(img, 0, 0);

        // Estampa la firma en la esquina inferior derecha, ~28% del ancho
        const firmaAncho = img.width * 0.28;
        const firmaAlto = firmaAncho * (firmaImg.height / firmaImg.width);
        const margen = img.width * 0.03;
        ctx.drawImage(
          firmaImg,
          img.width - firmaAncho - margen,
          img.height - firmaAlto - margen,
          firmaAncho,
          firmaAlto
        );

        const resultado = out.toDataURL('image/jpeg', 0.92);
        this.pages.update(pages => pages.map((p, i) =>
          i === this.currentPageIndex() ? { ...p, image: resultado } : p
        ));
        this.cerrarFirma();
      };
      firmaImg.src = firmaDataUrl;
    };
    img.src = pagina.image;
  }

  // ── UTILIDADES GENERALES ───────────────────────────

  private stopStream() {
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
  }

  reset() {
    this.mode.set('idle');
    this.pages.set([]);
    this.currentPageIndex.set(0);
    this.errorMsg.set(null);
    this.carnetFront.set(null);
    this.carnetBack.set(null);
    this.carnetStep.set('front');
    this.extractedData.set(null);
    this.mostrarFirma.set(false);
    this.stopStream();
  }

  setScanType(type: 'document' | 'carnet') {
    this.scanType.set(type);
    this.reset();
  }
}
