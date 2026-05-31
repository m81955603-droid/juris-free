import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SupabaseService } from '../services/supabase.service';
import { map, take } from 'rxjs/operators';

export const authGuard: CanActivateFn = () => {
  const supabase = inject(SupabaseService);
  const router   = inject(Router);
  return supabase.isAuthenticated$.pipe(
    take(1),
    map(isAuth => isAuth ? true : router.createUrlTree(['/login']))
  );
};