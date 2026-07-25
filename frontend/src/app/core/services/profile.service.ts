import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, firstValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface MiEstado {
  rol: 'admin' | 'abogado';
  estado: 'pendiente' | 'aprobado' | 'rechazado';
  en_prueba: boolean;
  minutos_restantes: number;
}

@Injectable({ providedIn: 'root' })
export class ProfileService {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl + '/api/v1/admin';

  private estadoSubject = new BehaviorSubject<MiEstado | null>(null);
  estado$ = this.estadoSubject.asObservable();

  /** Consulta el backend y guarda el resultado. Se debe llamar tras el login. */
  async cargarEstado(): Promise<MiEstado | null> {
    try {
      const estado = await firstValueFrom(this.http.get<MiEstado>(`${this.apiUrl}/mi-estado`));
      this.estadoSubject.next(estado);
      return estado;
    } catch {
      this.estadoSubject.next(null);
      return null;
    }
  }

  get estadoActual(): MiEstado | null {
    return this.estadoSubject.value;
  }

  get esAdmin(): boolean {
    return this.estadoSubject.value?.rol === 'admin';
  }

  limpiar() {
    this.estadoSubject.next(null);
  }
}
