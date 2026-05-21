import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: '/chat', pathMatch: 'full' },
  { path: 'chat',         loadComponent: () => import('./features/chat/chat.component').then(m => m.ChatComponent) },
  { path: 'analyzer',     loadComponent: () => import('./features/analyzer/analyzer.component').then(m => m.AnalyzerComponent) },
  { path: 'repository',   loadComponent: () => import('./features/repository/repository.component').then(m => m.RepositoryComponent) },
  { path: 'documents',    loadComponent: () => import('./features/documents/documents.component').then(m => m.DocumentsComponent) },
  { path: 'my-templates', loadComponent: () => import('./features/my-templates/my-templates.component').then(m => m.MyTemplatesComponent) },
  { path: 'library',      loadComponent: () => import('./features/library/library.component').then(m => m.LibraryComponent) },
  { path: 'cases',        loadComponent: () => import('./features/cases/cases.component').then(m => m.CasesComponent) },
  { path: 'calendar',     loadComponent: () => import('./features/calendar/calendar.component').then(m => m.CalendarComponent) },
  { path: 'settings',     loadComponent: () => import('./features/settings/settings.component').then(m => m.SettingsComponent) },
  { path: 'auth/callback', loadComponent: () => import('./core/auth-callback/auth-callback.component').then(m => m.AuthCallbackComponent) },
  { path: '**', redirectTo: '/chat' }
];
