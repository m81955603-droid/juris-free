-- JURIS-FREE Bolivia — Schema Supabase
-- Ejecutar en: Supabase Dashboard -> SQL Editor

-- Habilitar extension pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- Tabla de documentos legales bolivianos
CREATE TABLE IF NOT EXISTS legal_documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type          TEXT NOT NULL CHECK (type IN ('ley','decreto','sentencia','resolucion','constitucion')),
    title         TEXT NOT NULL,
    body          TEXT NOT NULL,
    source_url    TEXT,
    published_date DATE,
    jurisdiction  TEXT DEFAULT 'nacional',
    area          TEXT NOT NULL,
    embedding     vector(384),
    metadata      JSONB DEFAULT '{}',
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de conversaciones
CREATE TABLE IF NOT EXISTS conversations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title         TEXT NOT NULL DEFAULT 'Nueva consulta',
    area          TEXT DEFAULT 'auto',
    message_count INT DEFAULT 0,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de mensajes
CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('user','assistant')),
    content         TEXT NOT NULL,
    provider_used   TEXT,
    tokens_used     INT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Indice vectorial para busqueda semantica (IVFFlat)
CREATE INDEX IF NOT EXISTS legal_docs_embedding_idx
    ON legal_documents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Indice de texto completo para busqueda hibrida
CREATE INDEX IF NOT EXISTS legal_docs_fts_idx
    ON legal_documents USING gin(to_tsvector('spanish', title || ' ' || body));

-- Funcion de busqueda semantica
CREATE OR REPLACE FUNCTION match_legal_documents(
    query_embedding vector(384),
    match_threshold FLOAT DEFAULT 0.7,
    match_count     INT   DEFAULT 5,
    filter_area     TEXT  DEFAULT NULL
)
RETURNS TABLE (
    id TEXT, type TEXT, title TEXT, body TEXT,
    source_url TEXT, area TEXT, similarity FLOAT
)
LANGUAGE plpgsql AS
'BEGIN
  RETURN QUERY
  SELECT
    d.id::TEXT, d.type, d.title,
    LEFT(d.body, 500) AS body,
    d.source_url, d.area,
    1 - (d.embedding <=> query_embedding) AS similarity
  FROM legal_documents d
  WHERE
    (filter_area IS NULL OR d.area = filter_area)
    AND 1 - (d.embedding <=> query_embedding) > match_threshold
  ORDER BY d.embedding <=> query_embedding
  LIMIT match_count;
END;';

-- Row Level Security
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "usuarios ven sus conversaciones"
    ON conversations FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "usuarios ven sus mensajes"
    ON messages FOR ALL
    USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

-- Legal documents es publico (solo lectura)
ALTER TABLE legal_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "documentos legales publicos"
    ON legal_documents FOR SELECT USING (true);

SELECT 'Schema JURIS-FREE Bolivia creado OK' AS resultado;
