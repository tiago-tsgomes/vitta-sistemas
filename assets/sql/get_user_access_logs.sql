-- ─────────────────────────────────────────────────────────────
-- Logs de acesso dos usuários (exclusivo ADMIN_GLOBAL)
-- Retorna: nome, usuário (email), perfil, empresa,
--          último acesso NA EMPRESA (USUARIO.ULTIMO_ACESSO_EMP,
--          ver set_ultimo_acesso_empresa.sql), plataforma do
--          último acesso (web/app) e data de criação.
--
-- Execute este SQL no Supabase Dashboard > SQL Editor.
-- ─────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_user_access_logs();

CREATE OR REPLACE FUNCTION public.get_user_access_logs()
RETURNS TABLE (
  id_usu        uuid,
  nome          text,
  usuario       text,
  perfil        text,
  id_emp        uuid,
  empresa       text,
  ultimo_acesso timestamptz,
  plataforma    text,
  criado_em     timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Somente ADMIN_GLOBAL pode consultar os logs
  IF NOT EXISTS (
    SELECT 1
    FROM public."USUARIO" u
    WHERE u."AUTH_ID" = auth.uid()
      AND u."TIPO_USU" = 'ADMIN_GLOBAL'
  ) THEN
    RAISE EXCEPTION 'Acesso negado: apenas Admin Global pode consultar os logs de acesso.';
  END IF;

  RETURN QUERY
  SELECT
    u."ID_USU",
    u."NOME_USU"::text,
    u."EMAIL_USU"::text,
    u."TIPO_USU"::text,
    u."ID_EMP",
    e."NOME_EMP"::text,
    u."ULTIMO_ACESSO_EMP",
    u."ULTIMO_ACESSO_PLATAFORMA",
    u."DTCRI_USU"::timestamptz
  FROM public."USUARIO" u
  LEFT JOIN public."EMPRESA"  e  ON e."ID_EMP" = u."ID_EMP"
  ORDER BY u."ULTIMO_ACESSO_EMP" DESC NULLS LAST, u."NOME_USU";
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_access_logs() TO authenticated;
