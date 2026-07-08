-- JURIS-FREE Bolivia — Migracion: clientes + plantillas_usuario con RLS real
-- Ejecutar en: Supabase Dashboard -> SQL Editor
-- Fecha: seguridad — cierra el hueco donde /clientes y /plantillas
-- devolvian los datos de TODOS los abogados sin filtrar.

-- ─────────────────────────────────────────────────────────────
-- TABLA CLIENTES (CRM legal)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clientes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre      TEXT NOT NULL,
    ci_nit      TEXT DEFAULT '',
    telefono    TEXT DEFAULT '',
    email       TEXT DEFAULT '',
    direccion   TEXT DEFAULT '',
    ciudad      TEXT DEFAULT 'La Paz',
    tipo        TEXT DEFAULT 'persona_natural' CHECK (tipo IN ('persona_natural','persona_juridica')),
    notas       TEXT DEFAULT '',
    user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Si la tabla ya existia sin user_id (creada "a mano" en algun momento), agregarla:
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_clientes_user   ON clientes(user_id);
CREATE INDEX IF NOT EXISTS idx_clientes_nombre ON clientes(nombre);

ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "clientes_rls" ON clientes;
CREATE POLICY "clientes_rls" ON clientes
    FOR ALL USING (auth.uid() = user_id OR user_id IS NULL);


-- ─────────────────────────────────────────────────────────────
-- TABLA PLANTILLAS_USUARIO (Mis Plantillas — estilo personal del abogado)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS plantillas_usuario (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre             TEXT NOT NULL,
    tipo_documento     TEXT DEFAULT 'general',
    texto_original     TEXT DEFAULT '',
    ficha_estilo       TEXT DEFAULT '',
    tono               TEXT DEFAULT 'formal',
    resumen_estilo     TEXT DEFAULT '',
    system_prompt      TEXT DEFAULT '',
    variables          TEXT DEFAULT '[]',
    user_id            UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at         TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE plantillas_usuario ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_plantillas_user ON plantillas_usuario(user_id);

ALTER TABLE plantillas_usuario ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "plantillas_rls" ON plantillas_usuario;
CREATE POLICY "plantillas_rls" ON plantillas_usuario
    FOR ALL USING (auth.uid() = user_id OR user_id IS NULL);

SELECT 'Migracion clientes + plantillas_usuario con RLS aplicada OK' AS resultado;
