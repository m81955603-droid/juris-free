-- JURIS-FREE Bolivia / ALSAMI — Sesion unica por abogado
-- Evita que la misma cuenta (email+password o Google) se use desde
-- 2 dispositivos distintos al mismo tiempo. Cuando alguien inicia
-- sesion, se guarda un identificador unico de esa sesion; cualquier
-- sesion anterior de la misma cuenta queda invalidada automaticamente
-- en su siguiente peticion al backend.
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor

ALTER TABLE usuarios_perfil ADD COLUMN IF NOT EXISTS sesion_activa_id TEXT;

-- Cada quien puede actualizar SU PROPIA fila (necesario para que el
-- backend, impersonando al usuario, pueda registrar su sesion actual
-- como la valida). El backend solo envia el campo sesion_activa_id,
-- nunca deja que el usuario cambie su propio rol/estado por esta via.
DROP POLICY IF EXISTS "actualizar_propia_sesion" ON usuarios_perfil;
CREATE POLICY "actualizar_propia_sesion" ON usuarios_perfil
    FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

SELECT 'sesion_activa_id agregada, sesion unica por abogado lista' AS resultado;
