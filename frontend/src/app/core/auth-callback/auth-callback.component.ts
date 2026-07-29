import { Component, OnInit, OnDestroy, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { SupabaseService } from '../services/supabase.service';

/**
 * Pagina de callback de OAuth (Google). Supabase procesa el token que
 * viene en la URL de forma asincrona; antes esta pagina esperaba un
 * tiempo fijo (1.5s) y navegaba a ciegas, lo que fallaba si la sesion
 * tardaba un poco mas en establecerse (sobre todo en cuentas nuevas o
 * conexiones lentas) — te mandaba a /chat sin sesion real y el guard
 * te devolvia al login sin ningun aviso.
 *
 * Ahora esperamos activamente a que la sesion este realmente lista
 * (con reintentos), y solo entonces navegamos.
 */
@Component({
  selector: 'app-auth-callback',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="callback-screen">
      <div class="spinner"></div>
      <p>{{ mensaje() }}</p>
    </div>
  `,
  styles: [`
    .callback-screen {
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      height: 100vh; gap: 16px; font-family: 'DM Sans', Georgia, serif; color: #1a3a5c;
    }
    .spinner {
      width: 32px; height: 32px; border: 3px solid #e2e8f0; border-top-color: #1a3a5c;
      border-radius: 50%; animation: spin .8s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
  `]
})
export class AuthCallbackComponent implements OnInit, OnDestroy {
  private router = inject(Router);
  private supabase = inject(SupabaseService);
  private intervalo?: ReturnType<typeof setInterval>;
  private intentos = 0;

  mensaje = signal('Autenticando...');

  ngOnInit(): void {
    this.verificarSesion();
    // Reintenta cada 400ms por hasta ~8 segundos, por si la sesion
    // tarda en establecerse desde el token de la URL.
    this.intervalo = setInterval(() => this.verificarSesion(), 400);
  }

  ngOnDestroy(): void {
    if (this.intervalo) clearInterval(this.intervalo);
  }

  private async verificarSesion() {
    this.intentos++;
    const token = await this.supabase.getAccessToken();

    if (token) {
      if (this.intervalo) clearInterval(this.intervalo);
      await this.supabase.registrarSesionActual();
      this.router.navigate(['/chat']);
      return;
    }

    if (this.intentos >= 20) {
      // ~8 segundos sin lograr sesion: algo salio mal de verdad
      if (this.intervalo) clearInterval(this.intervalo);
      this.mensaje.set('No se pudo iniciar sesión. Redirigiendo...');
      setTimeout(() => this.router.navigate(['/login']), 1500);
    }
  }
}
