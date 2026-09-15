-- ============================================================
-- FIX DEFINITIVO — Database error querying schema + SECRETARIA
-- Execute em: https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- Cada bloco é independente; erros individuais não param o script.
-- ============================================================

-- PASSO 1: Corrige campos NULL em auth.users (um por vez)
-- Se algum campo não existir nesta versão do GoTrue, o bloco
-- captura o erro e continua sem parar o script inteiro.

DO $$ BEGIN
  UPDATE auth.users SET email_change = '' WHERE email_change IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'email_change: %', SQLERRM;
END $$;

DO $$ BEGIN
  UPDATE auth.users SET confirmation_token = '' WHERE confirmation_token IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'confirmation_token: %', SQLERRM;
END $$;

DO $$ BEGIN
  UPDATE auth.users SET recovery_token = '' WHERE recovery_token IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'recovery_token: %', SQLERRM;
END $$;

DO $$ BEGIN
  UPDATE auth.users SET email_change_token_new = '' WHERE email_change_token_new IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'email_change_token_new: %', SQLERRM;
END $$;

DO $$ BEGIN
  UPDATE auth.users SET email_change_token_current = '' WHERE email_change_token_current IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'email_change_token_current: %', SQLERRM;
END $$;

DO $$ BEGIN
  UPDATE auth.users SET reauthentication_token = '' WHERE reauthentication_token IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'reauthentication_token: %', SQLERRM;
END $$;

-- PASSO 2: Recria create_usuario_empresa
--   • SECRETARIA pode criar usuários
--   • Colunas base seguras no INSERT (evita falha por coluna ausente)
--   • UPDATE pós-insert tenta corrigir campos opcionais sem quebrar

DROP FUNCTION IF EXISTS public.create_usuario_empresa(text,text,uuid,uuid,text,uuid,text);
DROP FUNCTION IF EXISTS public.create_usuario_empresa(text,text,uuid,uuid,text,uuid);
DROP FUNCTION IF EXISTS public.create_usuario_empresa(text,text,uuid,uuid,text);
DROP FUNCTION IF EXISTS public.create_usuario_empresa(text,text,uuid,uuid);

CREATE OR REPLACE FUNCTION public.create_usuario_empresa(
  p_email     text,
  p_nome      text,
  p_cargo_id  uuid,
  p_id_emp    uuid,
  p_tel       text  DEFAULT NULL,
  p_prof_id   uuid  DEFAULT NULL,
  p_senha     text  DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
  v_caller_tipo text;
  v_new_uid     uuid;
  v_tipo_usu    text;
  v_descr_cargo text;
BEGIN
  v_caller_tipo := (auth.jwt()->'user_metadata'->>'tipo_usu');
  IF v_caller_tipo NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO', 'SECRETARIA') THEN
    RAISE EXCEPTION 'Sem permissão para criar usuários';
  END IF;

  SELECT "DESCR_CARGO" INTO v_descr_cargo
  FROM "CARGO" WHERE "ID_CARGO" = p_cargo_id;

  v_tipo_usu := CASE v_descr_cargo
    WHEN 'ADMINISTRADOR' THEN 'ADMIN_EMPRESA'
    WHEN 'SECRETARIA'    THEN 'SECRETARIA'
    WHEN 'PROFISSIONAL'  THEN 'PROFISSIONAL'
    WHEN 'AUTONOMO'      THEN 'AUTONOMO'
    ELSE 'USUARIO'
  END;

  -- INSERT com colunas base garantidas + email_change já como ''
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_user_meta_data, raw_app_meta_data, created_at, updated_at,
    role, aud,
    confirmation_token, recovery_token, email_change,
    is_super_admin, is_sso_user, deleted_at
  )
  SELECT
    gen_random_uuid(),
    instance_id,
    lower(trim(p_email)),
    extensions.crypt(p_senha, extensions.gen_salt('bf', 10)),
    now(),
    jsonb_build_object(
      'nome_usu',              p_nome,
      'tipo_usu',              v_tipo_usu,
      'ativo_usu',             true,
      'ID_EMP',                p_id_emp,
      'force_password_change', true
    ),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    now(), now(),
    'authenticated', 'authenticated',
    '', '', '',
    false, false, NULL
  FROM auth.users
  LIMIT 1
  RETURNING id INTO v_new_uid;

  -- Tenta corrigir campos opcionais que podem existir dependendo da versão
  BEGIN
    UPDATE auth.users SET
      email_change_token_new     = COALESCE(email_change_token_new, ''),
      email_change_token_current = COALESCE(email_change_token_current, ''),
      reauthentication_token     = COALESCE(reauthentication_token, '')
    WHERE id = v_new_uid;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- coluna não existe nesta versão, sem problema
  END;

  INSERT INTO "USUARIO" (
    "AUTH_ID", "NOME_USU", "EMAIL_USU", "TEL_USU",
    "TIPO_USU", "CARGO_USU", "ATIVO_USU", "ID_EMP", "PROF_USU", "DTCRI_USU"
  )
  VALUES (
    v_new_uid, p_nome, lower(trim(p_email)), p_tel,
    v_tipo_usu, p_cargo_id, true, p_id_emp, p_prof_id, now()
  );

  RETURN v_new_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_usuario_empresa(text,text,uuid,uuid,text,uuid,text) TO authenticated;

-- ------------------------------------------------------------
-- PASSO 3: Permite SECRETARIA excluir usuários da empresa
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_usuario_empresa(
  p_id      uuid,
  p_auth_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_tipo text;
BEGIN
  v_caller_tipo := (auth.jwt()->'user_metadata'->>'tipo_usu');
  IF v_caller_tipo NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO', 'SECRETARIA') THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;

  DELETE FROM "USUARIO" WHERE "ID_USU" = p_id;

  IF p_auth_id IS NOT NULL THEN
    DELETE FROM auth.users WHERE id = p_auth_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_usuario_empresa(uuid,uuid) TO authenticated;
