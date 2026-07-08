import { Component, signal, ElementRef, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { inject } from '@angular/core';

type ScanMode = 'idle' | 'camera' | 'processing' | 'result';

@Component({
  selector: 'app-scanner',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './scanner.component.html',
  styleUrls: ['./scanner.component.scss']
})
export class ScannerComponent {
  private http = inject(HttpClient);

  @ViewChild('videoEl') videoEl!: ElementRef<HTMLVideoElement>;
  @ViewChild('canvasEl') canvasEl!: ElementRef<HTMLCanvasElement>;

  mode = signal<ScanMode>('idle');
  capturedImage = signal<string | null>(null);
  ocrResult = signal<string | null>(null);
  errorMsg = signal<string | null>(null);
  isLoading = signal(false);
  scanType = signal<'document' | 'carnet'>('document');

  // Para carnet: dos lados
  carnetFront = signal<string | null>(null);
  carnetBack = signal<string | null>(null);
  carnetStep = signal<'front' | 'back'>('front');
  extractedData = signal<any>(null);

  private stream: MediaStream | null = null;

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
        this.capturedImage.set(imageData);
        this.mode.set('result');
      } else {
        this.carnetBack.set(imageData);
        this.capturedImage.set(imageData);
        this.processCarnet();
      }
    } else {
      this.capturedImage.set(imageData);
      this.processDocument(imageData);
    }
  }

  private stopStream() {
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
  }

  private processDocument(imageData: string) {
    this.mode.set('processing');
    this.isLoading.set(true);
    const base64 = imageData.split(',')[1];
    const prompt = `Eres un asistente de OCR especializado en documentos legales bolivianos.
Extrae TODO el texto de este documento con máxima precisión.
Mantén el formato original: párrafos, títulos, numeración.
Si hay sellos o firmas, indícalos como [SELLO] o [FIRMA].
Responde SOLO con el texto extraído, sin comentarios adicionales.`;

    this.callGeminiVision(base64, prompt).subscribe({
      next: (res: any) => {
        const text = res?.candidates?.[0]?.content?.parts?.[0]?.text || 'No se pudo extraer texto.';
        this.ocrResult.set(text);
        this.isLoading.set(false);
        this.mode.set('result');
      },
      error: () => {
        this.errorMsg.set('Error al procesar la imagen. Intenta nuevamente.');
        this.isLoading.set(false);
        this.mode.set('result');
      }
    });
  }

  private processCarnet() {
    this.mode.set('processing');
    this.isLoading.set(true);
    const frontBase64 = this.carnetFront()!.split(',')[1];
    const backBase64 = this.carnetBack()!.split(',')[1];

    const prompt = `Extrae los datos de esta carnet de identidad boliviana.
Responde ÚNICAMENTE en JSON con este formato exacto:
{
  "nombre_completo": "",
  "numero_ci": "",
  "fecha_nacimiento": "",
  "lugar_nacimiento": "",
  "fecha_expiracion": "",
  "estado_civil": "",
  "observaciones": ""
}
Si un campo no se ve claramente, dejarlo vacío.`;

    // Procesamos anverso primero
    this.callGeminiVision(frontBase64, prompt).subscribe({
      next: (res: any) => {
        const text = res?.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
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

  private callGeminiVision(base64: string, prompt: string) {
    return this.http.post('https://juris-free-backend.onrender.com/api/v1/ocr/scan', {
      image_base64: base64,
      mode: this.scanType(),
      mime_type: 'image/jpeg'
    });
  }



  copiado = signal(false);

  downloadPDF() {
    const img = this.capturedImage();
    if (!img) return;
    const link = document.createElement('a');
    link.href = img;
    link.download = `escaneado_${Date.now()}.jpg`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }

  async copyText() {
    const text = this.ocrResult();
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // Fallback para navegadores/webviews que bloquean el Clipboard API
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
    this.copiado.set(true);
    setTimeout(() => this.copiado.set(false), 2000);
  }

  sendToAnalyzer() {
    const text = this.ocrResult();
    if (text) {
      sessionStorage.setItem('scanner_ocr_text', text);
      window.location.href = '/analyzer';
    }
  }

  reset() {
    this.mode.set('idle');
    this.capturedImage.set(null);
    this.ocrResult.set(null);
    this.errorMsg.set(null);
    this.carnetFront.set(null);
    this.carnetBack.set(null);
    this.carnetStep.set('front');
    this.extractedData.set(null);
    this.stopStream();
  }

  captureCarnetBack() {
    this.carnetStep.set('back');
    this.mode.set('idle');
  }

  setScanType(type: 'document' | 'carnet') {
    this.scanType.set(type);
    this.reset();
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

  copyCarnetData() {
    const data = this.extractedData();
    if (data) {
      navigator.clipboard.writeText(JSON.stringify(data, null, 2));
    }
  }
}



