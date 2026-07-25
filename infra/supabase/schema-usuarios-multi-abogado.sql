-- JURIS-FREE Bolivia — Sistema multi-abogado con aprobacion manual
-- Ejecutar en: Supabase Dashboard -> SQL Editor

-- ─────────────────────────────────────────────────────────────
-- TABLA usuarios_perfil
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS usuarios_perfil (
    id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email             TEXT NOT NULL,
    nombre            TEXT DEFAULT '',
    rol               TEXT NOT NULL DEFAULT 'abogado' CHECK (rol IN ('admin','abogado')),
    estado            TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobado','rechazado')),
    fecha_registro    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_aprobacion  TIMESTAMPTZ,
    aprobado_por      UUID REFERENCES auth.users(id)
);

ALTER TABLE usuarios_perfil ENABLE ROW LEVEL SECURITY;

-- Cada quien puede ver y crear (si falta) su propia fila.
-- La lista completa para el panel de admin la maneja el backend con
-- la service key, verificando primero que el que pregunta sea admin.
DROP POLICY IF EXISTS "ver_propio_perfil" ON usuarios_perfil;
CREATE POLICY "ver_propio_perfil" ON usuarios_perfil
    FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "crear_propio_perfil" ON usuarios_perfil;
CREATE POLICY "crear_propio_perfil" ON usuarios_perfil
    FOR INSERT WITH CHECK (auth.uid() = id);

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: crear perfil automaticamente al registrarse
-- (funciona tanto para registro con email/password como con Google)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION crear_perfil_nuevo_usuario()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO usuarios_perfil (id, email, nombre)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', '')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION crear_perfil_nuevo_usuario();

-- ─────────────────────────────────────────────────────────────
-- BACKFILL: crear perfil para usuarios que ya existian antes
-- de este cambio (si los hay)
-- ─────────────────────────────────────────────────────────────
INSERT INTO usuarios_perfil (id, email, nombre)
SELECT id, email, COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', '')
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- IMPORTANTE — PASO MANUAL:
-- Convierte tu propia cuenta en admin aprobado. Reemplaza el email
-- por el que usas para loguearte en el sistema, y corre esto aparte:
-- ─────────────────────────────────────────────────────────────
-- UPDATE usuarios_perfil
-- SET rol = 'admin', estado = 'aprobado', fecha_aprobacion = NOW()
-- WHERE email = 'TU_EMAIL_AQUI@gmail.com';

SELECT 'usuarios_perfil creado, trigger activo, backfill completo' AS resultado;
