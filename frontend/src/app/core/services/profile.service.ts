import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { BehaviorSubject, firstValueFrom } from 'rxjs';
import { pairwise, startWith } from 'rxjs/operators';
import { environment } from '../../../environments/environment';
import { SupabaseService } from './supabase.service';

export interface MiEstado {
  rol: 'admin' | 'abogado';
  estado: 'pendiente' | 'aprobado' | 'rechazado';
  en_prueba: boolean;
  minutos_restantes: number;
}

@Injectable({ providedIn: 'root' })
export class ProfileService {
  private http = inject(HttpClient);
  private supabase = inject(SupabaseService);
  private apiUrl = environment.apiUrl + '/api/v1/admin';

  private estadoSubject = new BehaviorSubject<MiEstado | null>(null);
  estado$ = this.estadoSubject.asObservable();

  constructor() {
    // Si la cuenta logueada cambia (login, logout, o cambio de cuenta
    // en la misma pestaña sin recargar la pagina), se borra el estado
    // cacheado. Sin esto, el rol/estado de la cuenta ANTERIOR se
    // quedaba "pegado" en pantalla hasta la siguiente consulta manual,
    // lo cual podia mostrar por error el panel de Administracion a
    // alguien que no es admin.
    this.supabase.currentUser$.pipe(
      startWith(null),
      pairwise()
    ).subscribe(([anterior, actual]) => {
      const idAnterior = anterior?.id ?? null;
      const idActual = actual?.id ?? null;
      if (idAnterior !== idActual) {
        this.estadoSubject.next(null);
      }
    });
  }

  /**
   * Consulta el backend y guarda el resultado. Se debe llamar tras el login.
   *
   * IMPORTANTE: distinguimos dos tipos de error:
   * - 401/403 (el backend RECHAZA explicitamente el acceso: cuenta
   *   rechazada, o prueba de 1h vencida) -> devolvemos un estado
   *   sintetico 'rechazado' para que el guard bloquee de inmediato.
   * - Cualquier otro error (backend caido, sin red, etc.) -> null,
   *   para no dejar a todo el mundo sin poder entrar por un problema
   *   temporal ajeno a su cuenta.
   */
  async cargarEstado(): Promise<MiEstado | null> {
    try {
      const estado = await firstValueFrom(this.http.get<MiEstado>(`${this.apiUrl}/mi-estado`));
      this.estadoSubject.next(estado);
      return estado;
    } catch (err) {
      if (err instanceof HttpErrorResponse && (err.status === 401 || err.status === 403)) {
        const bloqueado: MiEstado = { rol: 'abogado', estado: 'rechazado', en_prueba: false, minutos_restantes: 0 };
        this.estadoSubject.next(bloqueado);
        return bloqueado;
      }
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
