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

      <button class="btn-google" (click)="loginWithGoogle()" [disabled]="loading()">
        <svg viewBox="0 0 24 24" width="20" height="20"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>
        Continuar con Google
      </button>
      <div class="divider"><span>o</span></div>
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
    .btn-google {
      width: 100%;
      padding: 0.85rem;
      background: white;
      color: #1e293b;
      border: none;
      border-radius: 10px;
      font-size: 0.95rem;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 0.75rem;
      margin-bottom: 0.75rem;
      transition: opacity 0.2s;
    }
    .btn-google:hover:not(:disabled) { opacity: 0.9; }
    .btn-google:disabled { opacity: 0.5; cursor: not-allowed; }
    .divider {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin: 0.75rem 0;
      color: rgba(255,255,255,0.3);
      font-size: 0.8rem;
    }
    .divider::before, .divider::after {
      content: '';
      flex: 1;
      height: 1px;
      background: rgba(255,255,255,0.1);
    }
  `]
})
export class LoginComponent {
  private supabase = inject(SupabaseService);
  private router   = inject(Router);

  email    = '';
  password = '';
  loading  = signal(false);
  error    = signal('');

  loginWithGoogle() {
    this.loading.set(true);
    this.error.set('');
    this.supabase.signInWithGoogle().subscribe({
      error: () => {
        this.error.set('Error al conectar con Google.');
        this.loading.set(false);
      }
    });
  }

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

