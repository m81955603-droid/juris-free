import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { ProfileService } from '../services/profile.service';

export const adminGuard: CanActivateFn = async () => {
  const profile = inject(ProfileService);
  const router  = inject(Router);

  // Siempre se vuelve a consultar al backend (nunca confiar en el
  // estado en cache), para evitar que quede "pegado" el rol de una
  // cuenta anterior si se cambia de usuario en la misma pestaña.
  const estado = await profile.cargarEstado();
  if (estado?.rol === 'admin') return true;

  return router.createUrlTree(['/chat']);
};
