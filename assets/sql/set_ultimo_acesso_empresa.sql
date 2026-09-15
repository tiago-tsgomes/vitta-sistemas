-- ─────────────────────────────────────────────────────────────
-- Registra o último acesso do usuário NA EMPRESA que ele
-- efetivamente selecionou no login (diferente de
-- auth.users.last_sign_in_at, que é único por conta e por isso
-- aparecia repetido em todas as empresas de um mesmo login
-- multi-empresa). Chamado pelo cliente (index.html) dentro de
-- runPostLoginChecks, logo após confirmar que o usuário está ativo.
--
-- Execute este SQL no Supabase Dashboard > SQL Editor.
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public."USUARIO" ADD COLUMN IF NOT EXISTS "ULTIMO_ACESSO_EMP" timestamptz;

DROP FUNCTION IF EXISTS public.set_ultimo_acesso_empresa(uuid);

CREATE OR REPLACE FUNCTION public.set_ultimo_acesso_empresa(p_id_emp uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public."USUARIO"
  SET "ULTIMO_ACESSO_EMP" = now()
  WHERE "AUTH_ID" = auth.uid()
    AND ("ID_EMP" = p_id_emp OR ("ID_EMP" IS NULL AND p_id_emp IS NULL));
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_ultimo_acesso_empresa(uuid) TO authenticated;
