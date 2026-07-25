import { Component, OnInit, OnDestroy, signal, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { ProfileService } from '../../core/services/profile.service';
import { SupabaseService } from '../../core/services/supabase.service';

@Component({
  selector: 'app-pendiente',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './pendiente.component.html',
  styleUrls: ['./pendiente.component.scss']
})
export class PendienteComponent implements OnInit, OnDestroy {
  private profile = inject(ProfileService);
  private supabase = inject(SupabaseService);
  private router = inject(Router);
  private intervalo?: ReturnType<typeof setInterval>;

  estado = signal<'pendiente' | 'rechazado' | 'cargando'>('cargando');
  enPrueba = signal(false);
  minutosRestantes = signal(0);

  async ngOnInit() {
    await this.consultar();
    // Revisa cada 30s por si el admin ya te aprobo, o si se acaba la hora de prueba
    this.intervalo = setInterval(() => this.consultar(), 30000);
  }

  ngOnDestroy() {
    if (this.intervalo) clearInterval(this.intervalo);
  }

  private async consultar() {
    const est = await this.profile.cargarEstado();
    if (!est) return;

    if (est.estado === 'aprobado') {
      this.router.navigateByUrl('/chat');
      return;
    }
    this.estado.set(est.estado === 'rechazado' ? 'rechazado' : 'pendiente');
    this.enPrueba.set(est.en_prueba);
    this.minutosRestantes.set(est.minutos_restantes);
  }

  async cerrarSesion() {
    await firstValueFrom(this.supabase.signOut());
    this.router.navigateByUrl('/login');
  }
}
