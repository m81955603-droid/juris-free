import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { from, switchMap, catchError, throwError, firstValueFrom } from 'rxjs';
import { SupabaseService } from '../services/supabase.service';
import { environment } from '../../../environments/environment';

/**
 * Agrega el JWT de la sesion de Supabase a cada request que va dirigida
 * al backend (environment.apiUrl). Sin esto, el backend no sabe quien
 * esta llamando y no puede aplicar Row Level Security por usuario.
 *
 * Ademas, detecta cuando el backend informa que esta sesion fue
 * reemplazada por un login en otro dispositivo (sesion unica por
 * cuenta) y cierra sesion localmente con un mensaje claro, en vez de
 * dejar la app en un estado confuso con errores sueltos.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  // Solo interceptar llamadas a nuestro backend, no a Supabase directo ni a terceros
  if (!req.url.startsWith(environment.apiUrl)) {
    return next(req);
  }

  const supabase = inject(SupabaseService);
  const router = inject(Router);

  return from(supabase.getAccessToken()).pipe(
    switchMap(token => {
      const authReq = token
        ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
        : req;

      return next(authReq).pipe(
        catchError((err: unknown) => {
          if (
            err instanceof HttpErrorResponse &&
            err.status === 401 &&
            typeof err.error?.detail === 'string' &&
            err.error.detail.includes('otro dispositivo')
          ) {
            firstValueFrom(supabase.signOut()).finally(() => {
              router.navigate(['/login'], { queryParams: { motivo: 'otro-dispositivo' } });
            });
          }
          return throwError(() => err);
        })
      );
    })
  );
};
