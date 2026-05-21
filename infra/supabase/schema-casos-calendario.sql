CREATE TABLE IF NOT EXISTS casos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo TEXT NOT NULL, cliente TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('civil','penal','familiar','laboral','comercial','constitucional','otro')),
    estado TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','en_espera','cerrado','archivado')),
    descripcion TEXT DEFAULT '', numero_expediente TEXT DEFAULT '',
    juzgado TEXT DEFAULT '', contraparte TEXT DEFAULT '',
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS caso_notas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caso_id UUID REFERENCES casos(id) ON DELETE CASCADE,
    contenido TEXT NOT NULL,
    tipo TEXT DEFAULT 'nota' CHECK (tipo IN ('nota','actuacion','recordatorio','documento')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS caso_timeline (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caso_id UUID REFERENCES casos(id) ON DELETE CASCADE,
    descripcion TEXT NOT NULL, fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    tipo TEXT DEFAULT 'actuacion', created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS calendario_eventos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo TEXT NOT NULL, descripcion TEXT DEFAULT '',
    fecha_inicio DATE NOT NULL, fecha_fin DATE, hora TEXT DEFAULT '09:00',
    tipo TEXT DEFAULT 'audiencia' CHECK (tipo IN ('audiencia','vencimiento','reunion','recordatorio','plazo','diligencia')),
    caso_id UUID REFERENCES casos(id) ON DELETE SET NULL,
    color TEXT DEFAULT '#2563eb', completado BOOLEAN DEFAULT FALSE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_casos_estado  ON casos(estado);
CREATE INDEX IF NOT EXISTS idx_notas_caso    ON caso_notas(caso_id);
CREATE INDEX IF NOT EXISTS idx_eventos_fecha ON calendario_eventos(fecha_inicio);
ALTER TABLE casos              ENABLE ROW LEVEL SECURITY;
ALTER TABLE caso_notas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE caso_timeline      ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendario_eventos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "casos_rls"    ON casos              FOR ALL USING (auth.uid()=user_id OR user_id IS NULL);
CREATE POLICY "notas_rls"    ON caso_notas         FOR ALL USING (caso_id IN (SELECT id FROM casos WHERE user_id=auth.uid() OR user_id IS NULL));
CREATE POLICY "timeline_rls" ON caso_timeline      FOR ALL USING (caso_id IN (SELECT id FROM casos WHERE user_id=auth.uid() OR user_id IS NULL));
CREATE POLICY "eventos_rls"  ON calendario_eventos FOR ALL USING (auth.uid()=user_id OR user_id IS NULL);
SELECT 'Tablas casos + calendario OK' AS resultado;
