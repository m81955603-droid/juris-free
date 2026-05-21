import { Component, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-auth-callback',
  standalone: true,
  imports: [CommonModule],
  template: `<div style="display:flex;align-items:center;justify-content:center;height:100vh;font-family:Georgia,serif;color:#1a3a5c">Autenticando...</div>`
})
export class AuthCallbackComponent implements OnInit {
  private router = inject(Router);
  ngOnInit(): void { setTimeout(() => this.router.navigate(['/chat']), 1500); }
}