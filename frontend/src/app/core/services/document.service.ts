import { Injectable } from '@angular/core';
import {
  Document, Paragraph, TextRun, HeadingLevel,
  AlignmentType, BorderStyle, PageBreak,
  Table, TableRow, TableCell, WidthType,
  Header, Footer, PageNumber, NumberFormat,
  Packer
} from 'docx';
import { saveAs } from 'file-saver';

export interface DocumentData {
  titulo: string;
  subtitulo?: string;
  ciudad?: string;
  fecha?: string;
  contenido: string;
  abogado?: string;
  matricula?: string;
}

@Injectable({ providedIn: 'root' })
export class DocumentService {

  /**
   * Exporta el contenido del chat a un documento Word profesional
   */
  async exportChatToWord(markdownContent: string, titulo: string): Promise<void> {
    const paragraphs = this.parseMarkdownToDocx(markdownContent);
    const doc = this.buildWordDocument({
      titulo,
      ciudad: 'La Paz',
      fecha: new Date().toLocaleDateString('es-BO', { day: 'numeric', month: 'long', year: 'numeric' }),
      contenido: markdownContent
    }, paragraphs);

    const buffer = await Packer.toBlob(doc);
    const filename = titulo.replace(/\s+/g, '_').toLowerCase() + '_' + new Date().toISOString().slice(0,10) + '.docx';
    saveAs(buffer, filename);
  }

  /**
   * Genera un documento legal formal (demanda, contrato, memorial)
   */
  async generateLegalDocument(data: DocumentData): Promise<void> {
    const paragraphs = this.parseMarkdownToDocx(data.contenido);
    const doc = this.buildWordDocument(data, paragraphs);
    const buffer = await Packer.toBlob(doc);
    const filename = data.titulo.replace(/\s+/g, '_').toLowerCase() + '.docx';
    saveAs(buffer, filename);
  }

  /**
   * Export simple a PDF via impresion del navegador
   */
  async exportChatToPdf(markdownContent: string, titulo: string): Promise<void> {
    const html = this.markdownToHtml(markdownContent);
    const win = window.open('', '_blank');
    if (!win) return;

    win.document.write(`
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>${titulo}</title>
        <style>
          @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;600;700&family=DM+Sans:wght@300;400;500&display=swap');
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: 'DM Sans', sans-serif; font-size: 11pt; line-height: 1.7; color: #1a1510; padding: 2cm 2.5cm; }
          .header { border-bottom: 2px solid #0f1f35; padding-bottom: 14px; margin-bottom: 24px; display: flex; justify-content: space-between; align-items: flex-end; }
          .logo-area h1 { font-family: 'Playfair Display', serif; font-size: 16pt; color: #0f1f35; }
          .logo-area p { font-size: 8pt; color: #7a7268; letter-spacing: .08em; text-transform: uppercase; }
          .doc-meta { text-align: right; font-size: 9pt; color: #7a7268; }
          h2 { font-family: 'Playfair Display', serif; font-size: 13pt; color: #0f1f35; margin: 18px 0 8px; border-bottom: 1px solid #e8e3d8; padding-bottom: 4px; }
          h3 { font-size: 11pt; font-weight: 500; color: #1a3352; margin: 14px 0 6px; }
          p { margin: 6px 0; }
          strong { color: #0f1f35; font-weight: 500; }
          code { font-family: monospace; background: #f4f2ee; padding: 1px 4px; border-radius: 3px; font-size: 9pt; }
          ul { padding-left: 18px; margin: 6px 0; }
          li { margin: 3px 0; }
          .footer { margin-top: 32px; border-top: 1px solid #e8e3d8; padding-top: 10px; font-size: 8pt; color: #7a7268; text-align: center; }
          @media print { body { padding: 1cm 1.5cm; } }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="logo-area">
            <h1>JURIS-FREE Bolivia</h1>
            <p>Sistema Juridico Inteligente · Open Source</p>
          </div>
          <div class="doc-meta">
            <p>${titulo}</p>
            <p>${new Date().toLocaleDateString('es-BO', { day: 'numeric', month: 'long', year: 'numeric' })}</p>
          </div>
        </div>
        <div class="content">${html}</div>
        <div class="footer">
          Generado por JURIS-FREE Bolivia · Este documento es de caracter informativo. No reemplaza el criterio profesional del abogado.
        </div>
        <script>window.onload = () => { window.print(); }<\/script>
      </body>
      </html>
    `);
    win.document.close();
  }

  private buildWordDocument(data: DocumentData, paragraphs: Paragraph[]): Document {
    const date = data.fecha || new Date().toLocaleDateString('es-BO', { day: 'numeric', month: 'long', year: 'numeric' });
    const city = data.ciudad || 'La Paz';

    return new Document({
      creator: 'JURIS-FREE Bolivia',
      title: data.titulo,
      description: 'Documento juridico generado por JURIS-FREE Bolivia',
      styles: {
        default: {
          document: {
            run: { font: 'Calibri', size: 22, color: '1a1510' },
            paragraph: { spacing: { after: 160, line: 280, lineRule: 'auto' } }
          }
        }
      },
      sections: [{
        properties: {
          page: {
            margin: { top: 1440, right: 1440, bottom: 1440, left: 1800 },
            size: { width: 12240, height: 15840 }
          }
        },
        headers: {
          default: new Header({
            children: [
              new Paragraph({
                children: [
                  new TextRun({ text: 'JURIS-FREE Bolivia', font: 'Calibri', size: 16, color: '0f1f35', bold: true }),
                  new TextRun({ text: '  ·  ' + data.titulo, font: 'Calibri', size: 16, color: '7a7268' })
                ],
                border: { bottom: { color: '0f1f35', size: 6, style: BorderStyle.SINGLE, space: 4 } }
              })
            ]
          })
        },
        footers: {
          default: new Footer({
            children: [
              new Paragraph({
                children: [
                  new TextRun({ text: city + ', ' + date + '   |   Pág. ', font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ children: [PageNumber.CURRENT], font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ text: ' de ', font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ children: [PageNumber.TOTAL_PAGES], font: 'Calibri', size: 16, color: '7a7268' }),
                  new TextRun({ text: '   |   JURIS-FREE Bolivia — Documento informativo', font: 'Calibri', size: 16, color: 'b8b0a0', italics: true })
                ],
                alignment: AlignmentType.CENTER,
                border: { top: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 4 } }
              })
            ]
          })
        },
        children: [
          new Paragraph({
            children: [
              new TextRun({ text: data.titulo, font: 'Calibri', size: 36, bold: true, color: '0f1f35' })
            ],
            heading: HeadingLevel.TITLE,
            spacing: { before: 0, after: 240 }
          }),
          ...(data.subtitulo ? [new Paragraph({
            children: [new TextRun({ text: data.subtitulo, font: 'Calibri', size: 24, color: '4a4438', italics: true })],
            spacing: { after: 120 }
          })] : []),
          new Paragraph({
            children: [
              new TextRun({ text: city + ', ', font: 'Calibri', size: 20, color: '7a7268' }),
              new TextRun({ text: date, font: 'Calibri', size: 20, color: '7a7268', bold: true })
            ],
            spacing: { after: 480 },
            border: { bottom: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 8 } }
          }),
          ...paragraphs,
          new Paragraph({
            children: [new TextRun({ text: '', size: 22 })],
            spacing: { before: 480, after: 0 },
            border: { top: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 8 } }
          }),
          new Paragraph({
            children: [
              new TextRun({ text: 'Generado por JURIS-FREE Bolivia', font: 'Calibri', size: 16, color: 'b8b0a0', italics: true })
            ],
            alignment: AlignmentType.CENTER
          }),
          new Paragraph({
            children: [
              new TextRun({ text: 'Este documento es de carácter informativo. No reemplaza el criterio y responsabilidad profesional del abogado habilitado.', font: 'Calibri', size: 16, color: 'b8b0a0', italics: true })
            ],
            alignment: AlignmentType.CENTER,
            spacing: { after: 0 }
          })
        ]
      }]
    });
  }

  private parseMarkdownToDocx(markdown: string): Paragraph[] {
    const lines = markdown.split('\n');
    const paragraphs: Paragraph[] = [];

    for (const line of lines) {
      if (!line.trim()) {
        paragraphs.push(new Paragraph({ children: [new TextRun({ text: '' })], spacing: { after: 80 } }));
        continue;
      }

      if (line.startsWith('## ')) {
        paragraphs.push(new Paragraph({
          children: [new TextRun({ text: line.replace('## ', ''), font: 'Calibri', size: 28, bold: true, color: '0f1f35' })],
          heading: HeadingLevel.HEADING_1,
          spacing: { before: 360, after: 160 },
          border: { bottom: { color: 'e8e3d8', size: 4, style: BorderStyle.SINGLE, space: 4 } }
        }));
        continue;
      }

      if (line.startsWith('### ')) {
        paragraphs.push(new Paragraph({
          children: [new TextRun({ text: line.replace('### ', ''), font: 'Calibri', size: 24, bold: true, color: '1a3352' })],
          heading: HeadingLevel.HEADING_2,
          spacing: { before: 240, after: 120 }
        }));
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('* ')) {
        const text = line.replace(/^[-*] /, '');
        paragraphs.push(new Paragraph({
          children: this.parseInlineMarkdown(text),
          bullet: { level: 0 },
          spacing: { after: 80 }
        }));
        continue;
      }

      paragraphs.push(new Paragraph({
        children: this.parseInlineMarkdown(line),
        spacing: { after: 120 }
      }));
    }

    return paragraphs;
  }

  private parseInlineMarkdown(text: string): TextRun[] {
    const runs: TextRun[] = [];
    const regex = /\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|(.+?)(?=\*\*|\*|`|$)/g;
    let match;

    while ((match = regex.exec(text)) !== null) {
      if (!match[0]) continue;

      if (match[1]) {
        runs.push(new TextRun({ text: match[1], font: 'Calibri', size: 22, bold: true, color: '0f1f35' }));
      } else if (match[2]) {
        runs.push(new TextRun({ text: match[2], font: 'Calibri', size: 22, italics: true, color: '4a4438' }));
      } else if (match[3]) {
        runs.push(new TextRun({ text: match[3], font: 'Courier New', size: 20, color: '1a3352' }));
      } else if (match[4]) {
        runs.push(new TextRun({ text: match[4], font: 'Calibri', size: 22, color: '1a1510' }));
      }
    }

    if (runs.length === 0) {
      runs.push(new TextRun({ text, font: 'Calibri', size: 22, color: '1a1510' }));
    }

    return runs;
  }

  private markdownToHtml(markdown: string): string {
    return markdown
      .replace(/^## (.+)$/gm, '<h2>$1</h2>')
      .replace(/^### (.+)$/gm, '<h3>$1</h3>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code>$1</code>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/(<li>.*<\/li>\n?)+/gs, '<ul>$&</ul>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br>');
  }
}