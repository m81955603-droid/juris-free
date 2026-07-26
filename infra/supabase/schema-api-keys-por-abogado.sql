-- JURIS-FREE Bolivia — Fase 2: API keys de IA propias por abogado
-- Ejecutar en: Supabase Dashboard -> SQL Editor
--
-- Cada abogado puede configurar sus propias claves gratuitas de los
-- proveedores de IA (Gemini, Groq, etc.) en Ajustes. Si no configura
-- ninguna, el sistema sigue usando las claves compartidas del sistema
-- (las que ya estan en Render) como respaldo automatico.

CREATE TABLE IF NOT EXISTS usuario_api_keys (
    user_id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    gemini_api_key     TEXT,
    groq_api_key       TEXT,
    cerebras_api_key   TEXT,
    openrouter_api_key TEXT,
    sambanova_api_key  TEXT,
    mistral_api_key    TEXT,
    updated_at         TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE usuario_api_keys ENABLE ROW LEVEL SECURITY;

-- Cada quien solo puede ver/crear/editar SU PROPIA fila. Nadie, ni
-- siquiera el super-admin, puede leer las claves de otro abogado
-- desde la app (son privadas de cada quien).
DROP POLICY IF EXISTS "propias_api_keys" ON usuario_api_keys;
CREATE POLICY "propias_api_keys" ON usuario_api_keys
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

SELECT 'usuario_api_keys creada con RLS (cada quien ve solo la suya)' AS resultado;
