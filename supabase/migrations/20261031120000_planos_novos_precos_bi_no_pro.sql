-- Novos preços dos planos e Vitta BI incluído no plano Pro.
-- Rodar ANTES de publicar o código que lê PLANO.TEM_BI_PLANO.

-- 1) Novos preços
UPDATE public."PLANO" SET "PRECO_PLANO" = 97.00  WHERE "NOME_PLANO" = 'Essencial';
UPDATE public."PLANO" SET "PRECO_PLANO" = 147.00 WHERE "NOME_PLANO" = 'Clínica';
UPDATE public."PLANO" SET "PRECO_PLANO" = 197.00 WHERE "NOME_PLANO" = 'Pro';

-- 2) Vitta BI passa a ser recurso de plano (Pro)
ALTER TABLE public."PLANO" ADD COLUMN IF NOT EXISTS "TEM_BI_PLANO" boolean NOT NULL DEFAULT false;
UPDATE public."PLANO" SET "TEM_BI_PLANO" = ("NOME_PLANO" = 'Pro');

-- 3) Regra única de acesso ao BI: plano com BI OU liberação manual (cortesia) na empresa
CREATE OR REPLACE FUNCTION public.empresa_tem_bi(p_id_emp uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  select coalesce(e."BI_ACESSO_EMP", false) or coalesce(p."TEM_BI_PLANO", false)
  from "EMPRESA" e left join "PLANO" p on p."ID_PLANO" = e."ID_PLANO"
  where e."ID_EMP" = p_id_emp
$$;
REVOKE ALL ON FUNCTION public.empresa_tem_bi(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.empresa_tem_bi(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.bi_check_access(p_id_emp uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
begin
  if p_id_emp is null then
    raise exception 'empresa não informada';
  end if;

  if not exists (
    select 1 from "USUARIO" u
    where u."AUTH_ID" = auth.uid()
      and u."ID_EMP" = p_id_emp
      and u."TIPO_USU" = 'ADMIN_EMPRESA'
  ) then
    raise exception 'acesso negado ao Vitta BI para esta empresa';
  end if;

  if not coalesce(public.empresa_tem_bi(p_id_emp), false) then
    raise exception 'Vitta BI não habilitado para esta empresa';
  end if;
end;
$$;

-- 4) Só o Admin Global (ou o servidor) pode liberar o BI como cortesia
CREATE OR REPLACE FUNCTION public.protect_empresa_billing_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (NEW."STATUS_EMP" IS DISTINCT FROM OLD."STATUS_EMP"
      OR NEW."ACESSO_ATE" IS DISTINCT FROM OLD."ACESSO_ATE"
      OR NEW."TRIAL_EXPIRA_EM" IS DISTINCT FROM OLD."TRIAL_EXPIRA_EM"
      OR NEW."ID_PLANO" IS DISTINCT FROM OLD."ID_PLANO"
      OR NEW."ASAAS_CUSTOMER_ID" IS DISTINCT FROM OLD."ASAAS_CUSTOMER_ID"
      OR NEW."ASAAS_SUBSCRIPTION_ID" IS DISTINCT FROM OLD."ASAAS_SUBSCRIPTION_ID"
      OR NEW."ISENTO_COBRANCA" IS DISTINCT FROM OLD."ISENTO_COBRANCA"
      OR NEW."BI_ACESSO_EMP" IS DISTINCT FROM OLD."BI_ACESSO_EMP")
     AND COALESCE(public.get_my_tipo_usu(),'') <> 'ADMIN_GLOBAL'
     AND COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION 'Sem permissão para alterar dados de cobrança/status/plano da empresa';
  END IF;
  RETURN NEW;
END;
$$;
