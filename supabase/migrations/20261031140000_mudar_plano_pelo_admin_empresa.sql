-- ============================================================
-- Permite que o Administrador da empresa troque o próprio plano
-- pela tela "Minha Empresa", de forma controlada.
--
-- A proteção protect_empresa_billing_fields continua bloqueando
-- qualquer alteração direta de plano/cobrança por quem não é
-- Admin Global. A troca de plano só passa pela função abaixo,
-- que confere o vínculo de Administrador e se o plano está ativo.
-- ============================================================

-- 1) Função de troca de plano (só a própria empresa, só plano ativo)
CREATE OR REPLACE FUNCTION public.mudar_plano_empresa(p_id_plano uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_emp uuid;
BEGIN
  v_emp := public.get_my_empresa_id();
  IF v_emp IS NULL OR NOT EXISTS (
    SELECT 1 FROM "USUARIO"
    WHERE "AUTH_ID" = auth.uid()
      AND "ID_EMP" = v_emp
      AND "TIPO_USU" = 'ADMIN_EMPRESA'
      AND COALESCE("ATIVO_USU", true)
  ) THEN
    RAISE EXCEPTION 'Sem permissão para mudar o plano';
  END IF;

  IF p_id_plano IS NULL OR NOT EXISTS (
    SELECT 1 FROM "PLANO" WHERE "ID_PLANO" = p_id_plano AND "ATIVO_PLANO" = true
  ) THEN
    RAISE EXCEPTION 'Plano inválido';
  END IF;

  -- Libera a troca de plano só dentro desta transação (o cliente não
  -- consegue definir essa configuração por conta própria).
  PERFORM set_config('vitta.troca_plano_autorizada', 'on', true);

  UPDATE "EMPRESA"
     SET "ID_PLANO" = p_id_plano, "DTALTER_EMP" = now()
   WHERE "ID_EMP" = v_emp;
END;
$$;
REVOKE ALL ON FUNCTION public.mudar_plano_empresa(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mudar_plano_empresa(uuid) TO authenticated, service_role;

-- 2) Proteção de cobrança: aceita a troca de plano feita pela função acima
--    (e só o plano — os demais campos continuam exclusivos do Admin Global)
CREATE OR REPLACE FUNCTION public.protect_empresa_billing_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_outros_mudaram boolean;
  v_plano_mudou    boolean;
BEGIN
  v_outros_mudaram :=
         NEW."STATUS_EMP"            IS DISTINCT FROM OLD."STATUS_EMP"
      OR NEW."ACESSO_ATE"            IS DISTINCT FROM OLD."ACESSO_ATE"
      OR NEW."TRIAL_EXPIRA_EM"       IS DISTINCT FROM OLD."TRIAL_EXPIRA_EM"
      OR NEW."ASAAS_CUSTOMER_ID"     IS DISTINCT FROM OLD."ASAAS_CUSTOMER_ID"
      OR NEW."ASAAS_SUBSCRIPTION_ID" IS DISTINCT FROM OLD."ASAAS_SUBSCRIPTION_ID"
      OR NEW."ISENTO_COBRANCA"       IS DISTINCT FROM OLD."ISENTO_COBRANCA"
      OR NEW."BI_ACESSO_EMP"         IS DISTINCT FROM OLD."BI_ACESSO_EMP";
  v_plano_mudou := NEW."ID_PLANO" IS DISTINCT FROM OLD."ID_PLANO";

  IF (v_outros_mudaram OR v_plano_mudou)
     AND COALESCE(public.get_my_tipo_usu(),'') <> 'ADMIN_GLOBAL'
     AND COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') <> 'service_role' THEN
    -- Única exceção: troca de plano autorizada por mudar_plano_empresa()
    IF v_plano_mudou AND NOT v_outros_mudaram
       AND COALESCE(current_setting('vitta.troca_plano_autorizada', true), '') = 'on' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Sem permissão para alterar dados de cobrança/status/plano da empresa';
  END IF;
  RETURN NEW;
END;
$$;
