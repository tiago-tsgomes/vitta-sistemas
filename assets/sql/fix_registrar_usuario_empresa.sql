-- ============================================================
-- FIX: registrar_usuario_empresa — cargo ADMINISTRADOR
-- Problema: usuário criado no cadastro ficava sem CARGO_USU
--           e era exibido como "Usuário" em vez de "Administrador"
-- Execute em: https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.registrar_usuario_empresa(
  p_auth_id  uuid,
  p_nome     text,
  p_email    text,
  p_id_emp   uuid,
  p_tel      text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cargo_id uuid;
BEGIN
  -- Busca o cargo ADMINISTRADOR para vincular ao admin da empresa
  SELECT "ID_CARGO" INTO v_cargo_id
  FROM "CARGO"
  WHERE "DESCR_CARGO" = 'ADMINISTRADOR'
  LIMIT 1;

  INSERT INTO "USUARIO" (
    "AUTH_ID", "NOME_USU", "EMAIL_USU", "TEL_USU",
    "TIPO_USU", "CARGO_USU", "ATIVO_USU", "ID_EMP", "DTCRI_USU"
  )
  VALUES (
    p_auth_id, p_nome, p_email, p_tel,
    'ADMIN_EMPRESA', v_cargo_id, true, p_id_emp, now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_usuario_empresa(uuid,text,text,uuid,text) TO anon;
GRANT EXECUTE ON FUNCTION public.registrar_usuario_empresa(uuid,text,text,uuid,text) TO authenticated;
