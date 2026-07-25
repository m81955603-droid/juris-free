import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { ProfileService } from '../services/profile.service';

export const adminGuard: CanActivateFn = async () => {
  const profile = inject(ProfileService);
  const router  = inject(Router);

  const estado = profile.estadoActual || await profile.cargarEstado();
  if (estado?.rol === 'admin') return true;

  return router.createUrlTree(['/chat']);
};
