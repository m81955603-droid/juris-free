import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, Subject } from 'rxjs';
import { environment } from '../../../environments/environment';
import { LlmMessage, LlmResponse, ProviderStatus } from '../models/legal.models';

@Injectable({ providedIn: 'root' })
export class LlmProxyService {
  private http = inject(HttpClient);

  chat(messages: LlmMessage[], systemPrompt?: string, preferredProvider?: string): Observable<LlmResponse> {
    return this.http.post<LlmResponse>(
      environment.apiUrl + '/api/v1/llm/chat',
      { messages, system: systemPrompt, maxTokens: 65536 },
      { headers: new HttpHeaders({ 'Content-Type': 'application/json' }) }
    );
  }

  chatWithContext(messages: LlmMessage[], docType: string): Observable<LlmResponse> {
    return this.http.post<LlmResponse>(
      environment.apiUrl + '/api/v1/llm/chat',
      { messages, maxTokens: 65536, useContext: true, docType },
      { headers: new HttpHeaders({ 'Content-Type': 'application/json' }) }
    );
  }

  chatStream(messages: LlmMessage[], systemPrompt?: string): Observable<{chunk: string, done: boolean, provider?: string, model?: string, tokens?: number, error?: string}> {
    const subject = new Subject<any>();

    const body = JSON.stringify({ messages, system: systemPrompt, maxTokens: 65536 });
    const url = environment.apiUrl + '/api/v1/llm/chat/stream';

    fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    }).then(async resp => {
      if (!resp.ok) {
        subject.error(new Error(`HTTP ${resp.status}`));
        return;
      }
      const reader = resp.body!.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6));
              subject.next(data);
              if (data.done) {
                subject.complete();
                return;
              }
            } catch {}
          }
        }
      }
      subject.complete();
    }).catch(err => subject.error(err));

    return subject.asObservable();
  }

  getUsageStats(): ProviderStatus[] {
    return [];
  }
}