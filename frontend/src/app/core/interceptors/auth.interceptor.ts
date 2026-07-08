import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { from, switchMap } from 'rxjs';
import { SupabaseService } from '../services/supabase.service';
import { environment } from '../../../environments/environment';

/**
 * Agrega el JWT de la sesion de Supabase a cada request que va dirigida
 * al backend (environment.apiUrl). Sin esto, el backend no sabe quien
 * esta llamando y no puede aplicar Row Level Security por usuario.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  // Solo interceptar llamadas a nuestro backend, no a Supabase directo ni a terceros
  if (!req.url.startsWith(environment.apiUrl)) {
    return next(req);
  }

  const supabase = inject(SupabaseService);

  return from(supabase.getAccessToken()).pipe(
    switchMap(token => {
      if (!token) {
        return next(req);
      }
      const authReq = req.clone({
        setHeaders: { Authorization: `Bearer ${token}` }
      });
      return next(authReq);
    })
  );
};
