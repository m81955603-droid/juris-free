import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LlmProxyService } from '../../core/services/llm-proxy.service';
import { DocumentService } from '../../core/services/document.service';

interface DocumentTemplate {
  id: string;
  nombre: string;
  descripcion: string;
  icon: string;
  campos: Campo[];
  systemPrompt: string;
}

interface Campo {
  id: string;
  label: string;
  tipo: 'text' | 'textarea' | 'select' | 'date';
  placeholder?: string;
  opciones?: string[];
  requerido?: boolean;
}

@Component({
  selector: 'app-documents',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './documents.component.html',
  styleUrls: ['./documents.component.scss']
})
export class DocumentsComponent {
  private llm    = inject(LlmProxyService);
  private docSvc = inject(DocumentService);

  selectedTemplate = signal<DocumentTemplate | null>(null);
  formData: Record<string, string> = {};
  isGenerating = signal(false);
  generatedContent = signal('');
  step = signal<'select' | 'form' | 'preview'>('select');

  readonly templates: DocumentTemplate[] = [
    {
      id: 'demanda-civil',
      nombre: 'Demanda Civil',
      descripcion: 'Demanda ordinaria civil según Ley 439',
      icon: '⚖',
      campos: [
        { id: 'demandante', label: 'Nombre del demandante', tipo: 'text', placeholder: 'Nombre completo', requerido: true },
        { id: 'demandado',  label: 'Nombre del demandado',  tipo: 'text', placeholder: 'Nombre completo', requerido: true },
        { id: 'objeto',     label: 'Objeto de la demanda',  tipo: 'textarea', placeholder: 'Describe el objeto de la demanda...', requerido: true },
        { id: 'hechos',     label: 'Hechos',                tipo: 'textarea', placeholder: 'Describe los hechos cronologicamente...', requerido: true },
        { id: 'juzgado',    label: 'Juzgado',               tipo: 'text', placeholder: 'Juzgado de Partido en lo Civil y Comercial N°...'},
        { id: 'ciudad',     label: 'Ciudad',                tipo: 'select', opciones: ['La Paz','Cochabamba','Santa Cruz','Oruro','Potosi','Sucre','Tarija','Trinidad','Cobija'] }
      ],
      systemPrompt: 'Redacta una demanda civil formal y profesional para Bolivia según la Ley 439 (Codigo Procesal Civil). Incluye: encabezado formal con otorosi, seccion de hechos, fundamentos de derecho con articulos especificos, petitorio claro. Usa lenguaje juridico boliviano formal.'
    },
    {
      id: 'contrato-compraventa',
      nombre: 'Contrato de Compraventa',
      descripcion: 'Contrato de compraventa de bien inmueble o mueble',
      icon: '📋',
      campos: [
        { id: 'vendedor',   label: 'Vendedor',        tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'comprador',  label: 'Comprador',       tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'bien',       label: 'Bien objeto del contrato', tipo: 'textarea', placeholder: 'Describe el bien detalladamente...', requerido: true },
        { id: 'precio',     label: 'Precio (Bs.)',    tipo: 'text', placeholder: '0.00', requerido: true },
        { id: 'forma-pago', label: 'Forma de pago',  tipo: 'select', opciones: ['Contado','En cuotas','Transferencia bancaria','A credito'] },
        { id: 'ciudad',     label: 'Ciudad',          tipo: 'select', opciones: ['La Paz','Cochabamba','Santa Cruz','Oruro','Potosi','Sucre','Tarija','Trinidad','Cobija'] }
      ],
      systemPrompt: 'Redacta un contrato de compraventa formal y completo para Bolivia segun el Codigo Civil (Ley 12760). Incluye: identificacion de las partes, objeto del contrato, precio y forma de pago, obligaciones de ambas partes, clausulas de garantia, clausula de saneamiento por eviccion, resolucion de controversias, firmas. Usa terminologia juridica boliviana correcta.'
    },
    {
      id: 'poder-notarial',
      nombre: 'Poder Notarial',
      descripcion: 'Poder especial o general para representacion legal',
      icon: '🏛',
      campos: [
        { id: 'poderdante', label: 'Poderdante (quien otorga)', tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'apoderado',  label: 'Apoderado (quien recibe)',  tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'tipo',       label: 'Tipo de poder',            tipo: 'select', opciones: ['Poder Especial','Poder General','Poder Especial Amplio'] },
        { id: 'facultades', label: 'Facultades otorgadas',     tipo: 'textarea', placeholder: 'Describe las facultades especificas...', requerido: true },
        { id: 'vigencia',   label: 'Vigencia',                 tipo: 'select', opciones: ['Sin fecha de vencimiento','1 año','2 años','Hasta revocacion expresa'] }
      ],
      systemPrompt: 'Redacta un poder notarial formal para Bolivia segun el Codigo Civil boliviano. Incluye: identificacion completa del poderdante y apoderado, tipo de poder, facultades otorgadas de manera clara y especifica, clausula de ratificacion, indicacion de que se otorga ante Notario de Fe Publica. Usa el lenguaje notarial boliviano correcto.'
    },
    {
      id: 'memorial',
      nombre: 'Memorial Judicial',
      descripcion: 'Memorial de solicitud o apelacion ante organo judicial',
      icon: '📄',
      campos: [
        { id: 'solicitante', label: 'Solicitante',        tipo: 'text', placeholder: 'Nombre completo', requerido: true },
        { id: 'autoridad',   label: 'Autoridad destinataria', tipo: 'text', placeholder: 'Juez/Tribunal destinatario', requerido: true },
        { id: 'expediente',  label: 'N° de Expediente',   tipo: 'text', placeholder: 'Número de expediente' },
        { id: 'objeto',      label: 'Objeto del memorial',tipo: 'textarea', placeholder: 'Describe lo que solicitas...', requerido: true },
        { id: 'fundamentos', label: 'Fundamentos',        tipo: 'textarea', placeholder: 'Base legal y argumental...' }
      ],
      systemPrompt: 'Redacta un memorial judicial boliviano formal y profesional. Incluye: encabezado correcto con autoridad, identificacion del solicitante, causa/expediente, otrosiDigo si corresponde, fundamentos de hecho y derecho con articulos del Codigo Procesal Civil boliviano (Ley 439), petitorio especifico y claro, formula de peticion boliviana estandar. Usa lenguaje juridico procesal boliviano.'
    },
    {
      id: 'contrato-trabajo',
      nombre: 'Contrato de Trabajo',
      descripcion: 'Contrato laboral según Ley General del Trabajo',
      icon: '👷',
      campos: [
        { id: 'empleador',  label: 'Empleador/Empresa',   tipo: 'text', placeholder: 'Nombre o razon social', requerido: true },
        { id: 'trabajador', label: 'Trabajador',           tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'cargo',      label: 'Cargo/Funcion',        tipo: 'text', placeholder: 'Cargo a desempenar', requerido: true },
        { id: 'salario',    label: 'Salario mensual (Bs)', tipo: 'text', placeholder: '0.00', requerido: true },
        { id: 'jornada',    label: 'Jornada',              tipo: 'select', opciones: ['8 horas diarias / 48 semanales','Tiempo parcial','Por obra o tarea'] },
        { id: 'modalidad',  label: 'Modalidad',            tipo: 'select', opciones: ['Indefinido','A plazo fijo','A prueba (90 dias)'] }
      ],
      systemPrompt: 'Redacta un contrato de trabajo formal para Bolivia segun la Ley General del Trabajo y su Decreto Reglamentario. Incluye: identificacion de las partes, objeto del contrato, jornada de trabajo, remuneracion con desglose de beneficios sociales (aguinaldo, vacaciones, AFP, CNS), obligaciones del trabajador y empleador, causales de rescision, ley aplicable. Cita los articulos especificos de la LGT boliviana.'
    },
    {
      id: 'denuncia-penal',
      nombre: 'Denuncia Penal',
      descripcion: 'Denuncia formal ante el Ministerio Publico',
      icon: '🚨',
      campos: [
        { id: 'denunciante', label: 'Denunciante',         tipo: 'text', placeholder: 'Nombre completo + CI', requerido: true },
        { id: 'denunciado',  label: 'Denunciado (si conoce)', tipo: 'text', placeholder: 'Nombre o descripcion' },
        { id: 'delito',      label: 'Delito presunto',     tipo: 'text', placeholder: 'Ej: estafa, robo, lesiones...', requerido: true },
        { id: 'hechos',      label: 'Descripcion de hechos', tipo: 'textarea', placeholder: 'Relata los hechos cronologicamente con fechas, lugares y circunstancias...', requerido: true },
        { id: 'pruebas',     label: 'Pruebas disponibles', tipo: 'textarea', placeholder: 'Describe las pruebas que puedes presentar...' }
      ],
      systemPrompt: 'Redacta una denuncia penal formal para Bolivia ante el Ministerio Publico segun el Codigo de Procedimiento Penal (Ley 1970). Incluye: identificacion del denunciante, descripcion clara de los hechos, tipificacion del delito segun el Codigo Penal boliviano (Ley 1768) con los articulos correspondientes, solicitud de investigacion, ofrecimiento de pruebas. Usa lenguaje juridico penal boliviano.'
    }
  ];

  selectTemplate(template: DocumentTemplate): void {
    this.selectedTemplate.set(template);
    this.formData = {};
    template.campos.forEach(c => this.formData[c.id] = '');
    this.generatedContent.set('');
    this.step.set('form');
  }

  async generateDocument(): Promise<void> {
    const template = this.selectedTemplate();
    if (!template) return;

    this.isGenerating.set(true);
    this.step.set('preview');

    const fieldsSummary = template.campos
      .map(c => `${c.label}: ${this.formData[c.id] || '(no especificado)'}`)
      .join('\n');

    const prompt = `${template.systemPrompt}

DATOS DEL DOCUMENTO:
${fieldsSummary}

Genera el documento completo, formal y listo para usar en Bolivia.`;

    try {
      this.llm.chatWithContext([{ role: "user", content: prompt }], template.id).subscribe({
        next: resp => {
          this.generatedContent.set(resp.content);
          this.isGenerating.set(false);
        },
        error: err => {
          this.generatedContent.set('**Error al generar:** ' + err.message);
          this.isGenerating.set(false);
        }
      });
    } catch (err) {
      this.isGenerating.set(false);
    }
  }

  async downloadWord(): Promise<void> {
    const template = this.selectedTemplate();
    if (!template || !this.generatedContent()) return;
    await this.docSvc.generateLegalDocument({
      titulo: template.nombre,
      ciudad: this.formData['ciudad'] || 'La Paz',
      contenido: this.generatedContent()
    });
  }

  async downloadPdf(): Promise<void> {
    const template = this.selectedTemplate();
    if (!template || !this.generatedContent()) return;
    await this.docSvc.exportChatToPdf(this.generatedContent(), template.nombre);
  }

  renderMarkdown(content: string): string {
    if (!content) return '';
    return content
      .replace(/^## (.+)$/gm, '<h3>$1</h3>')
      .replace(/^### (.+)$/gm, '<h4>$1</h4>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code>$1</code>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/(<li>.*<\/li>\n?)+/gs, '<ul>$&</ul>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br>');
  }

  backToTemplates(): void { this.step.set('select'); this.selectedTemplate.set(null); }
  backToForm(): void { this.step.set('form'); }
}

