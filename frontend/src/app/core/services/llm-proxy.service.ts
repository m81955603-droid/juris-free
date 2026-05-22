import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
import { LlmMessage, LlmResponse, ProviderStatus } from '../models/legal.models';

@Injectable({ providedIn: 'root' })
export class LlmProxyService {
  private http = inject(HttpClient);

  chat(messages: LlmMessage[], systemPrompt?: string, preferredProvider?: string): Observable<LlmResponse> {
    return this.http.post<LlmResponse>(
      environment.apiUrl + '/api/v1/llm/chat',
      { messages, system: systemPrompt, maxTokens: 4096 },
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

  getUsageStats(): ProviderStatus[] {
    return [];
  }
}
