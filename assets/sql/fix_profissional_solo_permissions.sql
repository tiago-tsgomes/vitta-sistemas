-- ============================================================
-- FIX: Garante que PROFISSIONAL em empresa solo tenha os
-- mesmos acessos que PROFISSIONAL em empresa Pro
-- (espelha o padrão de fix_autonomo_permissions.sql)
-- Execute em: https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. USUARIO: PROFISSIONAL pode ler todos da mesma empresa
--    (necessário para carregar nomes, dropdowns de usuários etc.)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "usuario_profissional_read_empresa" ON public."USUARIO";
CREATE POLICY "usuario_profissional_read_empresa" ON public."USUARIO"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "ID_EMP" = public.get_my_empresa_id()
  );

-- ------------------------------------------------------------
-- 2. PROFISSIONAL: PROFISSIONAL pode ler todos da mesma empresa
--    (necessário para dropdowns de profissional em agendamentos,
--     consultas, pacientes etc.)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "profissional_profissional_read_empresa" ON public."PROFISSIONAL";
CREATE POLICY "profissional_profissional_read_empresa" ON public."PROFISSIONAL"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  );

-- ------------------------------------------------------------
-- 3. PACIENTE: PROFISSIONAL pode ler/escrever pacientes
--    vinculados a ele (via PACIENTE_PROFISSIONAL) ou da empresa
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "paciente_profissional_read" ON public."PACIENTE";
CREATE POLICY "paciente_profissional_read" ON public."PACIENTE"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "EMP_PAC" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  );

DROP POLICY IF EXISTS "paciente_profissional_write" ON public."PACIENTE";
CREATE POLICY "paciente_profissional_write" ON public."PACIENTE"
  FOR ALL TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "EMP_PAC" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  )
  WITH CHECK (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "EMP_PAC" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  );

-- ------------------------------------------------------------
-- 4. AGENDAMENTO: PROFISSIONAL pode ler/escrever agendamentos
--    da empresa (já filtrado por prof no frontend)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "agendamento_profissional_read" ON public."AGENDAMENTO";
CREATE POLICY "agendamento_profissional_read" ON public."AGENDAMENTO"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  );

DROP POLICY IF EXISTS "agendamento_profissional_write" ON public."AGENDAMENTO";
CREATE POLICY "agendamento_profissional_write" ON public."AGENDAMENTO"
  FOR ALL TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  )
  WITH CHECK (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND "ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
  );

-- ------------------------------------------------------------
-- 5. CONSULTA: PROFISSIONAL pode ler/escrever prontuários
--    da empresa
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "consulta_profissional_read" ON public."CONSULTA";
CREATE POLICY "consulta_profissional_read" ON public."CONSULTA"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND EXISTS (
      SELECT 1 FROM public."AGENDAMENTO" a
      WHERE a."ID_AGD" = "CONSULTA"."ID_AGD"
        AND a."ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
    )
  );

DROP POLICY IF EXISTS "consulta_profissional_write" ON public."CONSULTA";
CREATE POLICY "consulta_profissional_write" ON public."CONSULTA"
  FOR ALL TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND EXISTS (
      SELECT 1 FROM public."AGENDAMENTO" a
      WHERE a."ID_AGD" = "CONSULTA"."ID_AGD"
        AND a."ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
    )
  )
  WITH CHECK (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'PROFISSIONAL'
    AND EXISTS (
      SELECT 1 FROM public."AGENDAMENTO" a
      WHERE a."ID_AGD" = "CONSULTA"."ID_AGD"
        AND a."ID_EMP" = (auth.jwt()->'user_metadata'->>'ID_EMP')::uuid
    )
  );

-- ------------------------------------------------------------
-- 6. AI_CONFIG: garante que PROFISSIONAL pode ler (já existe
--    essa policy, este DROP+CREATE é para reforçar)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "ai_config_profissional_read" ON public."AI_CONFIG";
CREATE POLICY "ai_config_profissional_read" ON public."AI_CONFIG"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') IN ('PROFISSIONAL', 'ADMIN_EMPRESA', 'AUTONOMO')
  );
