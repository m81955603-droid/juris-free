import { Injectable } from '@angular/core';
import { createClient, SupabaseClient, User, Session } from '@supabase/supabase-js';
import { BehaviorSubject, Observable, from } from 'rxjs';
import { map } from 'rxjs/operators';
import { environment } from '../../../environments/environment';
import { LegalDocument, Conversation, ChatMessage } from '../models/legal.models';

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  private client: SupabaseClient;
  private userSubject    = new BehaviorSubject<User | null>(null);
  private sessionSubject = new BehaviorSubject<Session | null>(null);

  readonly currentUser$    = this.userSubject.asObservable();
  readonly session$        = this.sessionSubject.asObservable();
  readonly isAuthenticated$ = this.currentUser$.pipe(map(u => !!u));

  constructor() {
    this.client = createClient(environment.supabaseUrl, environment.supabaseAnonKey, {
      auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
    });
    this.client.auth.onAuthStateChange((_event, session) => {
      this.sessionSubject.next(session);
      this.userSubject.next(session?.user ?? null);
    });
    this.client.auth.getSession().then(({ data: { session } }) => {
      this.sessionSubject.next(session);
      this.userSubject.next(session?.user ?? null);
    });
  }
signInWithPassword(email: string, password: string): Observable<void> {
  return from(
    this.client.auth.signInWithPassword({ email, password })
      .then(({ error }) => { if (error) throw error; })
  );
}

  signInWithGoogle(): Observable<void> {
    return from(
      this.client.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.origin + '/auth/callback' }
      }).then(({ error }) => { if (error) throw error; })
    );
  }

  signInWithMagicLink(email: string): Observable<void> {
    return from(
      this.client.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: window.location.origin + '/auth/callback' }
      }).then(({ error }) => { if (error) throw error; })
    );
  }

  signOut(): Observable<void> {
    return from(
      this.client.auth.signOut().then(({ error }) => { if (error) throw error; })
    );
  }

  searchLegal(queryEmbedding: number[], area?: string, limit = 5): Observable<LegalDocument[]> {
    return from(
      this.client.rpc('match_legal_documents', {
        query_embedding: queryEmbedding,
        match_threshold: 0.7,
        match_count: limit,
        filter_area: area ?? null
      }).then(({ data, error }) => {
        if (error) throw error;
        return (data as LegalDocument[]) ?? [];
      })
    );
  }

  getConversations(userId: string): Observable<Conversation[]> {
    return from(
      this.client.from('conversations')
        .select('*')
        .eq('user_id', userId)
        .order('updated_at', { ascending: false })
        .then(({ data, error }) => {
          if (error) throw error;
          return (data as Conversation[]) ?? [];
        })
    );
  }

  createConversation(userId: string, title: string, area: string): Observable<Conversation> {
    return from(
      this.client.from('conversations')
        .insert({ user_id: userId, title, area, message_count: 0 })
        .select()
        .single()
        .then(({ data, error }) => {
          if (error) throw error;
          return data as Conversation;
        })
    );
  }

  getMessages(conversationId: string): Observable<ChatMessage[]> {
    return from(
      this.client.from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true })
        .then(({ data, error }) => {
          if (error) throw error;
          return (data as ChatMessage[]) ?? [];
        })
    );
  }

  saveMessage(msg: Omit<ChatMessage, 'id' | 'timestamp'>): Observable<ChatMessage> {
    return from(
      this.client.from('messages')
        .insert(msg)
        .select()
        .single()
        .then(({ data, error }) => {
          if (error) throw error;
          return data as ChatMessage;
        })
    );
  }

  uploadCaseDocument(file: File, caseId: string, userId: string): Observable<string> {
    const path = userId + '/cases/' + caseId + '/' + file.name;
    return from(
      this.client.storage
        .from('case-documents')
        .upload(path, file, { upsert: true })
        .then(({ data, error }) => {
          if (error) throw error;
          return data.path;
        })
    );
  }
}