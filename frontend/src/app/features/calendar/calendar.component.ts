import { Component, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule, ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { CalendarService } from '../../core/services/calendar.service';

@Component({
  selector: 'app-calendar',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule],
  templateUrl: './calendar.component.html',
  styleUrls: ['./calendar.component.scss']
})
export class CalendarComponent implements OnInit {
  eventos      = signal<any[]>([]);
  vencimientos = signal<any[]>([]);
  plazos       = signal<any>({});
  cargando     = signal(false);
  vista        = signal<'mes'|'lista'|'nuevo'|'plazo'>('mes');
  resultadoPlazo = signal<any>(null);

  hoy        = new Date();
  mesActual  = signal(this.hoy.getMonth() + 1);
  anioActual = signal(this.hoy.getFullYear());

  form:      FormGroup;
  plazoForm: FormGroup;

  tipos  = ['audiencia','vencimiento','reunion','recordatorio','plazo','diligencia'];
  meses  = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
             'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
  colores: Record<string,string> = {
    audiencia:'#2563eb', vencimiento:'#dc2626', reunion:'#16a34a',
    recordatorio:'#d97706', plazo:'#7c3aed', diligencia:'#0891b2'
  };

  diasMes = computed(() => {
    const y = this.anioActual(), m = this.mesActual();
    const primerDia = new Date(y, m-1, 1).getDay();
    const total     = new Date(y, m, 0).getDate();
    const celdas: Array<{num:number; eventos:any[]}|null> = [];
    for (let i = 0; i < primerDia; i++) celdas.push(null);
    for (let d = 1; d <= total; d++) {
      const f = `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
      celdas.push({ num: d, eventos: this.eventos().filter(e => e.fecha_inicio === f) });
    }
    return celdas;
  });

  constructor(private svc: CalendarService, private fb: FormBuilder) {
    this.form = this.fb.group({
      titulo:       ['', Validators.required],
      descripcion:  [''],
      fecha_inicio: [this.hoy.toISOString().split('T')[0], Validators.required],
      hora:         ['09:00'],
      tipo:         ['audiencia', Validators.required],
      color:        ['#2563eb']
    });
    this.plazoForm = this.fb.group({
      tipo_plazo:   ['apelacion_civil', Validators.required],
      fecha_inicio: [this.hoy.toISOString().split('T')[0], Validators.required]
    });
  }

  ngOnInit() { this.cargar(); this.cargarVencimientos(); this.cargarPlazos(); }

  cargar() {
    this.cargando.set(true);
    this.svc.list(this.mesActual(), this.anioActual()).subscribe({
      next: r => { this.eventos.set(r.eventos || []); this.cargando.set(false); },
      error: () => this.cargando.set(false)
    });
  }

  cargarVencimientos() {
    this.svc.proximosVencimientos(7).subscribe(r => this.vencimientos.set(r.vencimientos || []));
  }

  cargarPlazos() {
    this.svc.getPlazos().subscribe(r => this.plazos.set(r.plazos || {}));
  }

  navMes(dir: number) {
    let m = this.mesActual() + dir;
    let a = this.anioActual();
    if (m > 12) { m = 1;  a++; }
    if (m < 1)  { m = 12; a--; }
    this.mesActual.set(m); this.anioActual.set(a);
    this.cargar();
  }

  guardar() {
    if (this.form.invalid) return;
    this.cargando.set(true);
    this.svc.create(this.form.value).subscribe({
      next: () => { this.form.reset(); this.cargar(); this.cargarVencimientos(); this.vista.set('mes'); },
      error: () => this.cargando.set(false)
    });
  }

  calcularPlazo() {
    if (this.plazoForm.invalid) return;
    const v = this.plazoForm.value;
    this.svc.calcularPlazo(v.tipo_plazo, v.fecha_inicio)
      .subscribe(r => this.resultadoPlazo.set(r));
  }

  agregarEventoPlazo() {
    const r = this.resultadoPlazo();
    if (!r) return;
    this.svc.create(r.evento_sugerido).subscribe(() => {
      this.cargar(); this.cargarVencimientos();
      this.resultadoPlazo.set(null); this.vista.set('mes');
    });
  }

  completar(id: string) {
    this.svc.update(id, { completado: true }).subscribe(() => {
      this.cargar(); this.cargarVencimientos();
    });
  }

  colorTipo(t: string) { return this.colores[t] || '#6b7280'; }
  esHoy(d: number) {
    return d === this.hoy.getDate() &&
           this.mesActual()  === this.hoy.getMonth()+1 &&
           this.anioActual() === this.hoy.getFullYear();
  }
  get plazosList() { return Object.keys(this.plazos()); }
}
