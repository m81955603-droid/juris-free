import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface Caso {
  id?: string; titulo: string; cliente: string;
  tipo: string; estado: string; descripcion?: string;
  numero_expediente?: string; juzgado?: string;
  contraparte?: string; fecha_inicio?: string;
}

@Injectable({ providedIn: 'root' })
export class CasesService {
  private api = `${environment.apiUrl}/api/v1/cases`;
  constructor(private http: HttpClient) {}
  list(f?: {estado?:string;tipo?:string;q?:string}): Observable<any> {
    let p = new HttpParams();
    if (f?.estado) p = p.set('estado', f.estado);
    if (f?.tipo)   p = p.set('tipo',   f.tipo);
    if (f?.q)      p = p.set('q',      f.q);
    return this.http.get(this.api, { params: p });
  }
  get(id: string): Observable<any>            { return this.http.get(`${this.api}/${id}`); }
  create(c: Caso): Observable<any>            { return this.http.post(this.api, c); }
  update(id: string, d: any): Observable<any> { return this.http.patch(`${this.api}/${id}`, d); }
  delete(id: string): Observable<any>         { return this.http.delete(`${this.api}/${id}`); }
  addNote(cid: string, contenido: string, tipo='nota'): Observable<any> {
    return this.http.post(`${this.api}/${cid}/notas`, {caso_id:cid, contenido, tipo});
  }
}
