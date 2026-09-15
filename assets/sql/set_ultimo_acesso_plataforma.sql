-- ─────────────────────────────────────────────────────────────
-- Registra a plataforma do último login do usuário: 'web',
-- 'ios' ou 'android'. Chamado pelo cliente (index.html) logo
-- após o login bem-sucedido, via Capacitor.getPlatform().
--
-- Execute este SQL no Supabase Dashboard > SQL Editor.
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public."USUARIO" ADD COLUMN IF NOT EXISTS "ULTIMO_ACESSO_PLATAFORMA" text;

DROP FUNCTION IF EXISTS public.set_ultimo_acesso_plataforma(text);

CREATE OR REPLACE FUNCTION public.set_ultimo_acesso_plataforma(p_plataforma text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF p_plataforma NOT IN ('web', 'ios', 'android') THEN
    RETURN;
  END IF;

  UPDATE public."USUARIO"
  SET "ULTIMO_ACESSO_PLATAFORMA" = p_plataforma
  WHERE "AUTH_ID" = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_ultimo_acesso_plataforma(text) TO authenticated;
