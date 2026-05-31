import { Component, signal, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { SupabaseService } from '../../core/services/supabase.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
<div class="login-wrapper">
  <div class="login-card">
    <div class="login-logo">
      <span class="logo-icon">⚖️</span>
      <h1>MAJA JURÍDICO</h1>
      <p>Bolivia · Sistema Legal</p>
    </div>

    <div class="login-form">
      <div class="field">
        <label>Correo electrónico</label>
        <input
          type="email"
          [(ngModel)]="email"
          placeholder="correo@ejemplo.com"
          [disabled]="loading()"
          (keydown.enter)="login()" />
      </div>
      <div class="field">
        <label>Contraseña</label>
        <input
          type="password"
          [(ngModel)]="password"
          placeholder="••••••••"
          [disabled]="loading()"
          (keydown.enter)="login()" />
      </div>

      <div class="error-msg" *ngIf="error()">{{ error() }}</div>

      <button class="btn-login" (click)="login()" [disabled]="loading()">
        {{ loading() ? 'Ingresando...' : 'Ingresar' }}
      </button>
    </div>
  </div>
</div>
  `,
  styles: [`
    .login-wrapper {
      min-height: 100vh;
      background: linear-gradient(135deg, #0f172a 0%, #1e293b 50%, #0f172a 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 1rem;
    }
    .login-card {
      background: rgba(255,255,255,0.05);
      backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 20px;
      padding: 3rem 2.5rem;
      width: 100%;
      max-width: 420px;
    }
    .login-logo {
      text-align: center;
      margin-bottom: 2.5rem;
    }
    .logo-icon {
      font-size: 3rem;
      display: block;
      margin-bottom: 0.75rem;
    }
    .login-logo h1 {
      color: white;
      font-size: 1.6rem;
      font-weight: 800;
      letter-spacing: 1px;
      margin: 0;
    }
    .login-logo p {
      color: rgba(255,255,255,0.5);
      font-size: 0.85rem;
      margin: 0.25rem 0 0;
    }
    .field {
      margin-bottom: 1.25rem;
    }
    .field label {
      display: block;
      color: rgba(255,255,255,0.7);
      font-size: 0.85rem;
      margin-bottom: 0.4rem;
      font-weight: 500;
    }
    .field input {
      width: 100%;
      padding: 0.75rem 1rem;
      background: rgba(255,255,255,0.08);
      border: 1px solid rgba(255,255,255,0.15);
      border-radius: 10px;
      color: white;
      font-size: 0.95rem;
      box-sizing: border-box;
      transition: border-color 0.2s;
    }
    .field input:focus {
      outline: none;
      border-color: rgba(102,126,234,0.8);
    }
    .field input::placeholder { color: rgba(255,255,255,0.3); }
    .field input:disabled { opacity: 0.5; }
    .error-msg {
      background: rgba(239,68,68,0.15);
      border: 1px solid rgba(239,68,68,0.3);
      color: #fca5a5;
      padding: 0.75rem 1rem;
      border-radius: 8px;
      font-size: 0.85rem;
      margin-bottom: 1rem;
    }
    .btn-login {
      width: 100%;
      padding: 0.85rem;
      background: linear-gradient(135deg, #667eea, #764ba2);
      color: white;
      border: none;
      border-radius: 10px;
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
      transition: opacity 0.2s, transform 0.1s;
    }
    .btn-login:hover:not(:disabled) { opacity: 0.9; transform: translateY(-1px); }
    .btn-login:disabled { opacity: 0.5; cursor: not-allowed; }
  `]
})
export class LoginComponent {
  private supabase = inject(SupabaseService);
  private router   = inject(Router);

  email    = '';
  password = '';
  loading  = signal(false);
  error    = signal('');

  login() {
    if (!this.email || !this.password) {
      this.error.set('Ingresa tu correo y contraseña.');
      return;
    }
    this.loading.set(true);
    this.error.set('');
    this.supabase.signInWithPassword(this.email, this.password).subscribe({
      next: () => this.router.navigate(['/chat']),
      error: (err) => {
        this.error.set('Credenciales incorrectas. Intenta de nuevo.');
        this.loading.set(false);
      }
    });
  }
}