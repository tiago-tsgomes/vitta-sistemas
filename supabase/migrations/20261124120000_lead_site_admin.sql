-- ============================================================
-- LEAD_SITE — contatos que chegam pelo site / landing page
-- Tela "Leads Site" (Administração → só Admin Global)
-- ============================================================

-- 1) Campos para o acompanhamento do lead pela equipe
ALTER TABLE public."LEAD_SITE"
  ADD COLUMN IF NOT EXISTS observacao    text,
  ADD COLUMN IF NOT EXISTS atualizado_em timestamptz;

-- 2) O site (sem login) continua só podendo CRIAR leads, sempre como "Novo"
--    e sem preencher os campos internos de acompanhamento.
DROP POLICY IF EXISTS "Site pode registrar lead" ON public."LEAD_SITE";
CREATE POLICY "Site pode registrar lead" ON public."LEAD_SITE"
  FOR INSERT TO anon, authenticated
  WITH CHECK (status = 'Novo' AND observacao IS NULL AND atualizado_em IS NULL);

-- 3) Somente o Admin Global (ativo) vê, edita e exclui os leads
DROP POLICY IF EXISTS "lead_site_admin_select" ON public."LEAD_SITE";
CREATE POLICY "lead_site_admin_select" ON public."LEAD_SITE"
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public."USUARIO" u
     WHERE u."AUTH_ID" = auth.uid() AND u."TIPO_USU" = 'ADMIN_GLOBAL' AND COALESCE(u."ATIVO_USU", true)));

DROP POLICY IF EXISTS "lead_site_admin_update" ON public."LEAD_SITE";
CREATE POLICY "lead_site_admin_update" ON public."LEAD_SITE"
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public."USUARIO" u
     WHERE u."AUTH_ID" = auth.uid() AND u."TIPO_USU" = 'ADMIN_GLOBAL' AND COALESCE(u."ATIVO_USU", true)))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public."USUARIO" u
     WHERE u."AUTH_ID" = auth.uid() AND u."TIPO_USU" = 'ADMIN_GLOBAL' AND COALESCE(u."ATIVO_USU", true)));

DROP POLICY IF EXISTS "lead_site_admin_delete" ON public."LEAD_SITE";
CREATE POLICY "lead_site_admin_delete" ON public."LEAD_SITE"
  FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public."USUARIO" u
     WHERE u."AUTH_ID" = auth.uid() AND u."TIPO_USU" = 'ADMIN_GLOBAL' AND COALESCE(u."ATIVO_USU", true)));
