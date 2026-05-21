export type LegalArea =
  | 'civil' | 'penal' | 'laboral'
  | 'constitucional' | 'administrativo'
  | 'comercial' | 'familiar' | 'auto';

export interface LegalDocument {
  id: string;
  type: 'ley' | 'decreto' | 'sentencia' | 'resolucion' | 'constitucion';
  title: string;
  body: string;
  sourceUrl?: string;
  publishedDate?: string;
  jurisdiction: 'nacional' | 'departamental';
  area: LegalArea;
  metadata: Record<string, unknown>;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
  provider?: string;
  tokensUsed?: number;
  isStreaming?: boolean;
}

export interface LlmMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface LlmResponse {
  content: string;
  provider: string;
  model: string;
  tokensUsed: number;
  latencyMs: number;
}

export interface Conversation {
  id: string;
  userId: string;
  title: string;
  area: LegalArea;
  createdAt: string;
  updatedAt: string;
  messageCount: number;
}

export interface ProviderStatus {
  provider: string;
  model: string;
  todayRequests: number;
  todayTokens: number;
  isLimited: boolean;
  dailyLimit: number;
}