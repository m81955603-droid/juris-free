import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError, tap } from 'rxjs/operators';
import { environment } from '../../../environments/environment';
import { LlmMessage, LlmResponse, ProviderStatus } from '../models/legal.models';

interface ProviderConfig {
  name: string;
  model: string;
  priority: number;
  maxRequestsPerDay: number;
}

@Injectable({ providedIn: 'root' })
export class LlmProxyService {
  private http = inject(HttpClient);
  private usageKey = 'juris_llm_usage';
  private rateLimitKey = 'juris_ratelimit';

  private readonly providers: ProviderConfig[] = [
    { name: 'gemini',     model: 'gemini-2.5-flash',           priority: 1, maxRequestsPerDay: 1500  },
    { name: 'groq',       model: 'llama-3.3-70b-versatile',    priority: 2, maxRequestsPerDay: 14400 },
    { name: 'cerebras',   model: 'llama3.3-70b',               priority: 3, maxRequestsPerDay: 14400 },
    { name: 'openrouter', model: 'qwen/qwen-2.5-72b-instruct', priority: 4, maxRequestsPerDay: 200   },
    { name: 'sambanova',  model: 'Meta-Llama-3.3-70B-Instruct',priority: 5, maxRequestsPerDay: 1000  }
  ];

  chat(messages: LlmMessage[], systemPrompt?: string, preferredProvider?: string): Observable<LlmResponse> {
    const ordered = this.getOrderedProviders(preferredProvider);
    return this.tryProviders(messages, systemPrompt, ordered, 0);
  }

  private tryProviders(
    messages: LlmMessage[],
    system: string | undefined,
    providers: ProviderConfig[],
    index: number
  ): Observable<LlmResponse> {
    if (index >= providers.length) {
      return throwError(() => new Error('Todos los proveedores LLM no disponibles.'));
    }
    const provider = providers[index];
    return this.callBackend(provider, messages, system).pipe(
      tap(r => this.trackUsage(provider.name, r.tokensUsed)),
      catchError(err => {
        console.warn('[LLM] ' + provider.name + ' fallo: ' + err.message);
        this.markRateLimited(provider.name);
        return this.tryProviders(messages, system, providers, index + 1);
      })
    );
  }

  private callBackend(
    provider: ProviderConfig,
    messages: LlmMessage[],
    system?: string
  ): Observable<LlmResponse> {
    return this.http.post<LlmResponse>(
      environment.apiUrl + '/api/v1/llm/chat',
      { provider: provider.name, model: provider.model, messages, system, maxTokens: 2048 },
      { headers: new HttpHeaders({ 'Content-Type': 'application/json' }) }
    );
  }


  chatWithContext(messages: LlmMessage[], docType: string): Observable<LlmResponse> {
    return this.http.post<LlmResponse>(
      environment.apiUrl + '/api/v1/llm/chat',
      { messages, maxTokens: 4096, useContext: true, docType },
      { headers: new HttpHeaders({ 'Content-Type': 'application/json' }) }
    );
  }
  private getOrderedProviders(preferred?: string): ProviderConfig[] {
    const available = this.providers.filter(p => !this.isRateLimited(p.name));
    if (preferred) {
      const pref = available.find(p => p.name === preferred);
      if (pref) return [pref, ...available.filter(p => p.name !== preferred)];
    }
    return available.sort((a, b) => a.priority - b.priority);
  }

  getUsageStats(): ProviderStatus[] {
    const usage = this.getUsage();
    const today = new Date().toDateString();
    return this.providers.map(p => ({
      provider: p.name,
      model: p.model,
      todayRequests: usage[p.name]?.[today]?.requests ?? 0,
      todayTokens:   usage[p.name]?.[today]?.tokens   ?? 0,
      isLimited:     this.isRateLimited(p.name),
      dailyLimit:    p.maxRequestsPerDay
    }));
  }

  private trackUsage(provider: string, tokens: number): void {
    const usage = this.getUsage();
    const today = new Date().toDateString();
    if (!usage[provider]) usage[provider] = {};
    if (!usage[provider][today]) usage[provider][today] = { requests: 0, tokens: 0 };
    usage[provider][today].requests++;
    usage[provider][today].tokens += tokens;
    localStorage.setItem(this.usageKey, JSON.stringify(usage));
  }

  private markRateLimited(provider: string): void {
    const limits = this.getRateLimits();
    limits[provider] = Date.now() + 1 * 60 * 1000;
    localStorage.setItem(this.rateLimitKey, JSON.stringify(limits));
  }

  private isRateLimited(provider: string): boolean {
    const limits = this.getRateLimits();
    if (!limits[provider]) return false;
    if (Date.now() > limits[provider]) {
      delete limits[provider];
      localStorage.setItem(this.rateLimitKey, JSON.stringify(limits));
      return false;
    }
    return true;
  }

  private getUsage(): Record<string, Record<string, { requests: number; tokens: number }>> {
    try { return JSON.parse(localStorage.getItem(this.usageKey) || '{}'); }
    catch { return {}; }
  }

  private getRateLimits(): Record<string, number> {
    try { return JSON.parse(localStorage.getItem(this.rateLimitKey) || '{}'); }
    catch { return {}; }
  }
}
