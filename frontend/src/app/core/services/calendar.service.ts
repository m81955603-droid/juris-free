import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class CalendarService {
  private api = `${environment.apiUrl}/api/v1/calendar`;
  constructor(private http: HttpClient) {}
  list(mes?:number, anio?:number, casoId?:string): Observable<any> {
    let p = new HttpParams();
    if (mes)    p = p.set('mes',    mes.toString());
    if (anio)   p = p.set('anio',   anio.toString());
    if (casoId) p = p.set('caso_id', casoId);
    return this.http.get(this.api, { params: p });
  }
  create(e: any): Observable<any>             { return this.http.post(this.api, e); }
  update(id: string, d: any): Observable<any> { return this.http.patch(`${this.api}/${id}`, d); }
  delete(id: string): Observable<any>         { return this.http.delete(`${this.api}/${id}`); }
  proximosVencimientos(dias=7): Observable<any> {
    return this.http.get(`${this.api}/proximos-vencimientos?dias=${dias}`);
  }
  calcularPlazo(tipo:string, fecha:string, casoId?:string): Observable<any> {
    return this.http.post(`${this.api}/calcular-plazo`, {tipo_plazo:tipo, fecha_inicio:fecha, caso_id:casoId});
  }
  getPlazos(): Observable<any> { return this.http.get(`${this.api}/plazos-bolivianos`); }
}
