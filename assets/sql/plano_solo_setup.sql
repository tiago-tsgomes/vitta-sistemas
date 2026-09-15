-- ============================================================
-- PLANO SOLO — Setup (v3)
-- Execute no Supabase SQL Editor:
-- https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- ============================================================

-- Remove versões anteriores
DROP FUNCTION IF EXISTS public.registrar_usuario_solo(uuid, text, text, uuid);
DROP FUNCTION IF EXISTS public.registrar_usuario_solo(uuid, text, text, uuid, text, text, date, text, text, text);

-- ------------------------------------------------------------
-- RPC principal: cria ESPECIALIDADE + PROFISSIONAL + USUARIO
-- Retorna JSON com { usu_id, prof_id } para uso no frontend
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_usuario_solo(
  p_auth_id  uuid,
  p_nome     text,
  p_email    text,
  p_id_emp   uuid,
  p_tel      text    DEFAULT NULL,
  p_cpf      text    DEFAULT NULL,
  p_dtnasc   date    DEFAULT NULL,
  p_especial text    DEFAULT NULL,
  p_conselho text    DEFAULT NULL,
  p_registro text    DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prof_id  uuid;
  v_usu_id   uuid;
  v_espec_id uuid;
  v_cargo_id uuid;
BEGIN
  -- 1. Busca cargo AUTONOMO
  SELECT "ID_CARGO" INTO v_cargo_id
  FROM "CARGO"
  WHERE "DESCR_CARGO" = 'AUTONOMO'
  LIMIT 1;

  -- 2. Cria especialização na empresa (se informada)
  IF p_especial IS NOT NULL THEN
    INSERT INTO "ESPECIALIDADE" ("ID_EMP", "NOME_ESPEC", "ATIVO_ESPEC", "DTCRI_ESPEC")
    VALUES (p_id_emp, p_especial, true, now())
    RETURNING "ID_ESPEC" INTO v_espec_id;
  END IF;

  -- 3. Cria o Profissional com todos os dados
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

  -- 4. Cria o Usuário AUTONOMO vinculado ao profissional e ao cargo
  INSERT INTO "USUARIO" (
    "AUTH_ID", "NOME_USU", "EMAIL_USU", "TEL_USU",
    "TIPO_USU", "CARGO_USU", "ATIVO_USU", "ID_EMP", "PROF_USU", "DTCRI_USU"
  )
  VALUES (
    p_auth_id, p_nome, p_email, p_tel,
    'AUTONOMO', v_cargo_id, true, p_id_emp, v_prof_id, now()
  )
  RETURNING "ID_USU" INTO v_usu_id;

  RETURN json_build_object('usu_id', v_usu_id, 'prof_id', v_prof_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_usuario_solo(uuid,text,text,uuid,text,text,date,text,text,text) TO anon;
GRANT EXECUTE ON FUNCTION public.registrar_usuario_solo(uuid,text,text,uuid,text,text,date,text,text,text) TO authenticated;

-- ------------------------------------------------------------
-- RPC auxiliar: atualiza foto em PROFISSIONAL e USUARIO
-- Chamada após upload no Storage (sessão já disponível)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.atualizar_foto_solo(
  p_prof_id  uuid,
  p_usu_id   uuid,
  p_foto_url text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE "PROFISSIONAL" SET "FOTO_PROF" = p_foto_url WHERE "ID_PROF" = p_prof_id;
  UPDATE "USUARIO"      SET "FOTO_USU"  = p_foto_url WHERE "ID_USU"  = p_usu_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.atualizar_foto_solo(uuid, uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.atualizar_foto_solo(uuid, uuid, text) TO authenticated;
