-- ============================================================
-- Segurança: acessos e permissões
-- Corrige funções que não conferiam a empresa de quem chama.
-- Pode ser rodado a qualquer momento (não depende de deploy).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Perfil e empresa "atuais" do usuário logado
--    Antes: pegava qualquer vínculo (LIMIT 1) — usuário com 2
--    empresas podia cair no perfil/empresa errados.
--    Agora: prefere o vínculo da empresa selecionada no login
--    (ID_EMP do token). Só escolhe entre os vínculos do próprio
--    usuário, então não dá acesso a nada além do que ele já tem.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_tipo_usu()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT "TIPO_USU" FROM public."USUARIO"
  WHERE "AUTH_ID" = auth.uid()
  ORDER BY ("ID_EMP"::text = (auth.jwt() -> 'user_metadata' ->> 'ID_EMP')) DESC NULLS LAST,
           COALESCE("ATIVO_USU", true) DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_my_empresa_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT "ID_EMP" FROM public."USUARIO"
  WHERE "AUTH_ID" = auth.uid()
  ORDER BY ("ID_EMP"::text = (auth.jwt() -> 'user_metadata' ->> 'ID_EMP')) DESC NULLS LAST,
           COALESCE("ATIVO_USU", true) DESC
  LIMIT 1;
$$;

-- ------------------------------------------------------------
-- 2) Criar usuário da empresa
--    + só cria na própria empresa (exceto Admin Global)
--    + Secretaria só cria Secretaria ou Profissional
--    + profissional vinculado precisa ser da mesma empresa
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_usuario_empresa(p_email text, p_nome text, p_cargo_id uuid, p_id_emp uuid, p_tel text DEFAULT NULL::text, p_prof_id uuid DEFAULT NULL::uuid, p_senha text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'auth'
AS $function$
DECLARE v_caller_tipo text; v_new_uid uuid; v_tipo_usu text; v_descr_cargo text;
BEGIN
  v_caller_tipo := public.get_my_tipo_usu();
  IF COALESCE(v_caller_tipo,'') NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO', 'SECRETARIA') THEN
    RAISE EXCEPTION 'Sem permissão para criar usuários';
  END IF;
  IF p_id_emp IS NULL THEN
    RAISE EXCEPTION 'Empresa não informada';
  END IF;
  IF v_caller_tipo <> 'ADMIN_GLOBAL' AND p_id_emp IS DISTINCT FROM public.get_my_empresa_id() THEN
    RAISE EXCEPTION 'Sem permissão para criar usuários em outra empresa';
  END IF;

  SELECT "DESCR_CARGO" INTO v_descr_cargo FROM "CARGO" WHERE "ID_CARGO" = p_cargo_id;
  v_tipo_usu := CASE v_descr_cargo
    WHEN 'ADMINISTRADOR' THEN 'ADMIN_EMPRESA'
    WHEN 'SECRETARIA'    THEN 'SECRETARIA'
    WHEN 'PROFISSIONAL'  THEN 'PROFISSIONAL'
    WHEN 'AUTONOMO'      THEN 'AUTONOMO'
    ELSE 'USUARIO'
  END;

  IF v_caller_tipo = 'SECRETARIA' AND v_tipo_usu NOT IN ('SECRETARIA', 'PROFISSIONAL') THEN
    RAISE EXCEPTION 'Secretaria só pode criar usuários Secretaria ou Profissional';
  END IF;

  IF p_prof_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "PROFISSIONAL" WHERE "ID_PROF" = p_prof_id AND "ID_EMP" = p_id_emp
  ) THEN
    RAISE EXCEPTION 'Profissional não pertence a esta empresa';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_user_meta_data, raw_app_meta_data, created_at, updated_at,
    role, aud, confirmation_token, recovery_token, email_change,
    is_super_admin, is_sso_user, deleted_at
  )
  SELECT gen_random_uuid(), instance_id, lower(trim(p_email)),
    extensions.crypt(p_senha, extensions.gen_salt('bf', 10)), now(),
    jsonb_build_object(
      'nome_usu', p_nome, 'tipo_usu', v_tipo_usu, 'ativo_usu', true,
      'ID_EMP', p_id_emp, 'force_password_change', true
    ),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    now(), now(), 'authenticated', 'authenticated', '', '', '',
    false, false, NULL
  FROM auth.users LIMIT 1
  RETURNING id INTO v_new_uid;
  BEGIN
    UPDATE auth.users SET email_change_token_new = '', email_change_token_current = '', reauthentication_token = ''
    WHERE id = v_new_uid;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  INSERT INTO "USUARIO" (
    "AUTH_ID","NOME_USU","EMAIL_USU","TEL_USU","TIPO_USU","CARGO_USU","ATIVO_USU","ID_EMP","PROF_USU","DTCRI_USU"
  ) VALUES (v_new_uid, p_nome, lower(trim(p_email)), p_tel, v_tipo_usu, p_cargo_id, true, p_id_emp, p_prof_id, now());
  RETURN v_new_uid;
END; $function$;

-- ------------------------------------------------------------
-- 3) Excluir usuário da empresa
--    + só exclui usuário da própria empresa (exceto Admin Global)
--    + nunca exclui Admin Global; Secretaria não exclui Administrador
--    + o login só é apagado se a pessoa não tiver vínculo com
--      outra empresa (antes apagava o login inteiro)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_usuario_empresa(p_id uuid, p_auth_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller_tipo text; v_alvo record;
BEGIN
  v_caller_tipo := public.get_my_tipo_usu();
  IF COALESCE(v_caller_tipo,'') NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO', 'SECRETARIA') THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;

  SELECT "ID_USU", "AUTH_ID", "ID_EMP", "TIPO_USU" INTO v_alvo FROM "USUARIO" WHERE "ID_USU" = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuário não encontrado';
  END IF;
  IF v_alvo."TIPO_USU" = 'ADMIN_GLOBAL' THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;
  IF v_caller_tipo <> 'ADMIN_GLOBAL' THEN
    IF v_alvo."ID_EMP" IS DISTINCT FROM public.get_my_empresa_id() THEN
      RAISE EXCEPTION 'Sem permissão para excluir usuários de outra empresa';
    END IF;
    IF v_caller_tipo = 'SECRETARIA' AND v_alvo."TIPO_USU" IN ('ADMIN_EMPRESA', 'AUTONOMO') THEN
      RAISE EXCEPTION 'Secretaria não pode excluir administradores';
    END IF;
  END IF;
  IF p_auth_id IS NOT NULL AND p_auth_id IS DISTINCT FROM v_alvo."AUTH_ID" THEN
    RAISE EXCEPTION 'Login não corresponde ao usuário';
  END IF;

  DELETE FROM "USUARIO" WHERE "ID_USU" = p_id;

  IF v_alvo."AUTH_ID" IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM "USUARIO" WHERE "AUTH_ID" = v_alvo."AUTH_ID") THEN
    DELETE FROM auth.users WHERE id = v_alvo."AUTH_ID";
  END IF;
END; $function$;

-- ------------------------------------------------------------
-- 4) Excluir profissional: só da própria empresa (exceto Admin Global)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_profissional(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller_tipo text; v_emp uuid;
BEGIN
  v_caller_tipo := public.get_my_tipo_usu();
  IF COALESCE(v_caller_tipo,'') NOT IN ('ADMIN_EMPRESA', 'ADMIN_GLOBAL', 'AUTONOMO') THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;
  SELECT "ID_EMP" INTO v_emp FROM "PROFISSIONAL" WHERE "ID_PROF" = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profissional não encontrado';
  END IF;
  IF v_caller_tipo <> 'ADMIN_GLOBAL' AND v_emp IS DISTINCT FROM public.get_my_empresa_id() THEN
    RAISE EXCEPTION 'Sem permissão para excluir profissionais de outra empresa';
  END IF;
  UPDATE "USUARIO" SET "PROF_USU" = NULL WHERE "PROF_USU" = p_id;
  DELETE FROM "PROFISSIONAL" WHERE "ID_PROF" = p_id;
END; $function$;

-- ------------------------------------------------------------
-- 5) Cadastro self-service
--    + versão antiga (5 parâmetros, sem uso) removida
--    + só aceita plano ativo e nome preenchido
--    + vincular o primeiro administrador só vale para empresa
--      criada há menos de 1 dia (evita "assumir" empresa antiga
--      que ainda não tem usuário)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.criar_empresa_self_service(text, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.criar_empresa_self_service(p_nome_emp text, p_cnpj text DEFAULT NULL::text, p_tel text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_id_plano uuid DEFAULT NULL::uuid, p_cep text DEFAULT NULL::text, p_logradouro text DEFAULT NULL::text, p_numero text DEFAULT NULL::text, p_complemento text DEFAULT NULL::text, p_bairro text DEFAULT NULL::text, p_cidade text DEFAULT NULL::text, p_uf text DEFAULT NULL::text, p_logo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF COALESCE(trim(p_nome_emp), '') = '' THEN
    RAISE EXCEPTION 'Nome da empresa é obrigatório';
  END IF;
  IF p_id_plano IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "PLANO" WHERE "ID_PLANO" = p_id_plano AND "ATIVO_PLANO" = true
  ) THEN
    RAISE EXCEPTION 'Plano inválido';
  END IF;
  INSERT INTO "EMPRESA" (
    "NOME_EMP","CNPJ_EMP","TEL_EMP","EMAIL_EMP","ID_PLANO",
    "ATIVO_EMP","DTCRI_EMP","DTALTER_EMP",
    "CEP_EMP","LOGRADOURO_EMP","NUMERO_EMP","COMPLEMENTO_EMP",
    "BAIRRO_EMP","CIDADE_EMP","UF_EMP","LOGO_EMP"
  ) VALUES (
    trim(p_nome_emp),p_cnpj,p_tel,p_email,p_id_plano,
    true,now(),now(),
    p_cep,p_logradouro,p_numero,p_complemento,
    p_bairro,p_cidade,p_uf,p_logo
  ) RETURNING "ID_EMP" INTO v_id;
  RETURN v_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.registrar_usuario_empresa(p_auth_id uuid, p_nome text, p_email text, p_id_emp uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_auth_id THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "EMPRESA" WHERE "ID_EMP" = p_id_emp AND "DTCRI_EMP" > now() - interval '1 day') THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF EXISTS (SELECT 1 FROM "USUARIO" WHERE "ID_EMP" = p_id_emp) THEN
    RAISE EXCEPTION 'Empresa já possui usuário responsável';
  END IF;
  INSERT INTO "USUARIO" (
    "ID_USU", "AUTH_ID", "NOME_USU", "EMAIL_USU", "TIPO_USU", "ATIVO_USU", "DTCRI_USU", "ID_EMP"
  ) VALUES (
    gen_random_uuid(), p_auth_id, p_nome, lower(trim(p_email)), 'ADMIN_EMPRESA', true, now(), p_id_emp
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.registrar_usuario_empresa(p_auth_id uuid, p_nome text, p_email text, p_id_emp uuid, p_tel text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cargo_id uuid;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_auth_id THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "EMPRESA" WHERE "ID_EMP" = p_id_emp AND "DTCRI_EMP" > now() - interval '1 day') THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF EXISTS (SELECT 1 FROM "USUARIO" WHERE "ID_EMP" = p_id_emp) THEN
    RAISE EXCEPTION 'Empresa já possui usuário responsável';
  END IF;
  SELECT "ID_CARGO" INTO v_cargo_id FROM "CARGO" WHERE "DESCR_CARGO" = 'ADMINISTRADOR' LIMIT 1;
  INSERT INTO "USUARIO" (
    "AUTH_ID", "NOME_USU", "EMAIL_USU", "TEL_USU", "TIPO_USU", "CARGO_USU", "ATIVO_USU", "ID_EMP", "DTCRI_USU"
  ) VALUES (
    p_auth_id, p_nome, p_email, p_tel, 'ADMIN_EMPRESA', v_cargo_id, true, p_id_emp, now()
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.registrar_usuario_solo(p_auth_id uuid, p_nome text, p_email text, p_id_emp uuid, p_tel text DEFAULT NULL::text, p_cpf text DEFAULT NULL::text, p_dtnasc date DEFAULT NULL::date, p_especial text DEFAULT NULL::text, p_conselho text DEFAULT NULL::text, p_registro text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_prof_id  uuid;
  v_usu_id   uuid;
  v_espec_id uuid;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_auth_id THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "EMPRESA" WHERE "ID_EMP" = p_id_emp AND "DTCRI_EMP" > now() - interval '1 day') THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF EXISTS (SELECT 1 FROM "USUARIO" WHERE "ID_EMP" = p_id_emp) THEN
    RAISE EXCEPTION 'Empresa já possui usuário responsável';
  END IF;

  IF p_especial IS NOT NULL THEN
    INSERT INTO "ESPECIALIDADE" ("ID_EMP", "NOME_ESPEC", "ATIVO_ESPEC", "DTCRI_ESPEC")
    VALUES (p_id_emp, p_especial, true, now())
    RETURNING "ID_ESPEC" INTO v_espec_id;
  END IF;

  INSERT INTO "PROFISSIONAL" (
    "ID_EMP", "NOME_PROF", "EMAIL_PROF", "TEL_PROF", "CPF_PROF",
    "DTNASC_PROF", "ESPECIAL_PROF", "ID_ESPEC",
    "CONSELHO_PROF", "REGISTRO_PROF", "ATIVO_PROF", "DTCRI_PROF"
  )
  VALUES (
    p_id_emp, p_nome, p_email, p_tel, p_cpf,
    p_dtnasc, p_especial, v_espec_id,
    p_conselho, p_registro, true, now()
  )
  RETURNING "ID_PROF" INTO v_prof_id;

  INSERT INTO "USUARIO" (
    "AUTH_ID", "NOME_USU", "EMAIL_USU", "TEL_USU",
    "TIPO_USU", "ATIVO_USU", "ID_EMP", "PROF_USU", "DTCRI_USU"
  )
  VALUES (
    p_auth_id, p_nome, p_email, p_tel,
    'AUTONOMO', true, p_id_emp, v_prof_id, now()
  )
  RETURNING "ID_USU" INTO v_usu_id;

  RETURN v_usu_id;
END;
$function$;

-- ------------------------------------------------------------
-- 6) Ajustes apontados pelo verificador do Supabase
-- ------------------------------------------------------------
ALTER FUNCTION public.protect_empresa_billing_fields() SET search_path = public;
ALTER FUNCTION public.sync_usuario_metadata() SET search_path = public;

-- Painéis do BI exigem login: tira a execução de quem não está logado
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS fn
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'bi\_%'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, public', r.fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.fn);
  END LOOP;
END $$;
