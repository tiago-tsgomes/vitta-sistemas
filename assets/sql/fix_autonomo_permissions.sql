-- ============================================================
-- FIX: Permissões do perfil AUTONOMO (Solo)
-- Execute em: https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. Corrige RLS da tabela AI_CONFIG para incluir AUTONOMO
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "ai_config_profissional_read" ON public."AI_CONFIG";
CREATE POLICY "ai_config_profissional_read" ON public."AI_CONFIG"
  FOR SELECT TO authenticated
  USING ((auth.jwt()->'user_metadata'->>'tipo_usu') IN ('PROFISSIONAL', 'ADMIN_EMPRESA', 'AUTONOMO'));

-- ------------------------------------------------------------
-- 2. Recria create_usuario_empresa incluindo AUTONOMO
--    (padrão SECURITY DEFINER com acesso direto ao auth.users)
-- ------------------------------------------------------------
-- Drop todas as versões existentes (podem ter assinaturas diferentes)
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
  IF v_caller_tipo NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO') THEN
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

  -- Cria usuário no Auth copiando instance_id de um usuário existente (obrigatório no GoTrue)
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_user_meta_data, raw_app_meta_data, created_at, updated_at,
    role, aud, confirmation_token, recovery_token,
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
    '', '',
    false, false, NULL
  FROM auth.users
  LIMIT 1
  RETURNING id INTO v_new_uid;

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
-- 3. Recria delete_profissional incluindo AUTONOMO
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_profissional(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_tipo text;
BEGIN
  v_caller_tipo := (auth.jwt()->'user_metadata'->>'tipo_usu');
  IF v_caller_tipo NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO') THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;

  UPDATE "USUARIO"     SET "PROF_USU" = NULL WHERE "PROF_USU" = p_id;
  DELETE FROM "PROFISSIONAL" WHERE "ID_PROF" = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_profissional(uuid) TO authenticated;

-- ------------------------------------------------------------
-- 4. Recria delete_usuario_empresa incluindo AUTONOMO
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
  IF v_caller_tipo NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO') THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;

  DELETE FROM "USUARIO"   WHERE "ID_USU"  = p_id;

  IF p_auth_id IS NOT NULL THEN
    DELETE FROM auth.users WHERE id = p_auth_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_usuario_empresa(uuid,uuid) TO authenticated;

-- ------------------------------------------------------------
-- 5. Permite AUTONOMO ler todos os usuários da sua empresa
-- ------------------------------------------------------------

-- Helper SECURITY DEFINER: busca ID_EMP do usuário logado sem passar por RLS
CREATE OR REPLACE FUNCTION public.get_my_empresa_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT "ID_EMP" FROM public."USUARIO" WHERE "AUTH_ID" = auth.uid() LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_empresa_id() TO authenticated;

-- Policy: AUTONOMO pode ver todos os usuários da mesma empresa
DROP POLICY IF EXISTS "usuario_autonomo_read_empresa" ON public."USUARIO";
CREATE POLICY "usuario_autonomo_read_empresa" ON public."USUARIO"
  FOR SELECT TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'AUTONOMO'
    AND "ID_EMP" = public.get_my_empresa_id()
  );

-- Policy: AUTONOMO pode inserir/atualizar/deletar usuários da mesma empresa
DROP POLICY IF EXISTS "usuario_autonomo_write_empresa" ON public."USUARIO";
CREATE POLICY "usuario_autonomo_write_empresa" ON public."USUARIO"
  FOR ALL TO authenticated
  USING (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'AUTONOMO'
    AND "ID_EMP" = public.get_my_empresa_id()
  )
  WITH CHECK (
    (auth.jwt()->'user_metadata'->>'tipo_usu') = 'AUTONOMO'
    AND "ID_EMP" = public.get_my_empresa_id()
  );

-- ------------------------------------------------------------
-- 6. Garante que o cargo AUTONOMO existe e corrige usuários
-- ------------------------------------------------------------
INSERT INTO "CARGO" ("DESCR_CARGO")
SELECT 'AUTONOMO'
WHERE NOT EXISTS (
  SELECT 1 FROM "CARGO" WHERE "DESCR_CARGO" = 'AUTONOMO'
);

UPDATE "USUARIO" u
SET "CARGO_USU" = c."ID_CARGO"
FROM "CARGO" c
WHERE c."DESCR_CARGO" = 'AUTONOMO'
  AND u."TIPO_USU" = 'AUTONOMO'
  AND (u."CARGO_USU" IS NULL
       OR u."CARGO_USU" NOT IN (
         SELECT "ID_CARGO" FROM "CARGO" WHERE "DESCR_CARGO" = 'AUTONOMO'
       ));
