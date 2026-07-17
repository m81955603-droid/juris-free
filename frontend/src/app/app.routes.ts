import { Routes } from '@angular/router';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  { path: '', redirectTo: '/login', pathMatch: 'full' },
  { path: 'login', loadComponent: () => import('./features/login/login.component').then(m => m.LoginComponent) },
  { path: 'chat',         canActivate: [authGuard], loadComponent: () => import('./features/chat/chat.component').then(m => m.ChatComponent) },
  { path: 'analyzer',     canActivate: [authGuard], loadComponent: () => import('./features/analyzer/analyzer.component').then(m => m.AnalyzerComponent) },
  { path: 'repository',   canActivate: [authGuard], loadComponent: () => import('./features/repository/repository.component').then(m => m.RepositoryComponent) },
  { path: 'documents',    canActivate: [authGuard], loadComponent: () => import('./features/documents/documents.component').then(m => m.DocumentsComponent) },
  { path: 'my-templates', canActivate: [authGuard], loadComponent: () => import('./features/my-templates/my-templates.component').then(m => m.MyTemplatesComponent) },
  { path: 'library',      canActivate: [authGuard], loadComponent: () => import('./features/library/library.component').then(m => m.LibraryComponent) },
  { path: 'cases',        canActivate: [authGuard], loadComponent: () => import('./features/cases/cases.component').then(m => m.CasesComponent) },
  { path: 'calendar',     canActivate: [authGuard], loadComponent: () => import('./features/calendar/calendar.component').then(m => m.CalendarComponent) },
  { path: 'clients',      canActivate: [authGuard], loadComponent: () => import('./features/clients/clients.component').then(m => m.ClientsComponent) },
  { path: 'settings',     canActivate: [authGuard], loadComponent: () => import('./features/settings/settings.component').then(m => m.SettingsComponent) },
  { path: 'search',       canActivate: [authGuard], loadComponent: () => import('./features/global-search/global-search.component').then(m => m.GlobalSearchComponent) },
  { path: 'scanner', canActivate: [authGuard], loadComponent: () => import('./features/scanner/scanner.component').then(m => m.ScannerComponent) },
  { path: 'converter', canActivate: [authGuard], loadComponent: () => import('./features/converter/converter.component').then(m => m.ConverterComponent) },
  { path: 'auth/callback', loadComponent: () => import('./core/auth-callback/auth-callback.component').then(m => m.AuthCallbackComponent) },
  { path: '**', redirectTo: '/login' }
];
