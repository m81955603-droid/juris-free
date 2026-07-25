import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SupabaseService } from '../services/supabase.service';
import { ProfileService } from '../services/profile.service';
import { take } from 'rxjs/operators';
import { firstValueFrom } from 'rxjs';

export const authGuard: CanActivateFn = async () => {
  const supabase = inject(SupabaseService);
  const profile  = inject(ProfileService);
  const router   = inject(Router);

  const isAuth = await firstValueFrom(supabase.isAuthenticated$.pipe(take(1)));
  if (!isAuth) return router.createUrlTree(['/login']);

  const estado = await profile.cargarEstado();

  // Si no se pudo consultar el estado (backend caido, etc.), dejamos pasar
  // para no bloquear el sistema por un problema temporal de red.
  if (!estado) return true;

  if (estado.estado === 'aprobado') return true;

  // Pendiente dentro de su hora de prueba: puede seguir usando el sistema
  if (estado.estado === 'pendiente' && estado.en_prueba) return true;

  // Rechazado, o pendiente con la prueba ya vencida
  return router.createUrlTree(['/pendiente']);
};
