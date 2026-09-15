-- Categoria 3 do roadmap do Financeiro (Vitta BI): ranking por profissional.
-- Substitui o painel "Receita por profissional" de bi/pages/financeiro.html,
-- que até aqui era só um SVG com barras fixas mockadas.
--
-- Uma única RPC cobre os 5 itens da categoria 3, um objeto por profissional
-- ATIVO da empresa (mesmo padrão de bi_financeiro_filtros):
--   - recebido no período + recebidoDeltaPct (ranking de receita e de
--     crescimento vêm do mesmo array, só muda o campo de ordenação no client)
--   - repasseClinica x liquidoProf lado a lado (mesma regra de PERC_PROF já
--     usada em bi_financeiro_resumo)
--   - ticketMedio (recebido ÷ atendimentos REALIZADA do profissional)
--   - taxaFaltaPct (FALTA ÷ (REALIZADA + FALTA) do profissional)
--
-- Segue o filtro de período do topo (mes/mes_passado/semestre/ano, mesmas
-- janelas de comparação de bi_financeiro_resumo) mas propositalmente NÃO
-- aceita p_id_prof — é uma visão de comparação entre profissionais, não faz
-- sentido filtrar por um só.
--
-- Atribuição de profissional sempre via AGENDAMENTO.PROF_AGD (nunca
-- PAGAMENTO.ID_PROF direto), mesmo padrão de join das categorias 1 e 2.

create or replace function public.bi_financeiro_por_profissional(p_id_emp uuid, p_period text default 'mes')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;

  v_ini date;
  v_fim date;
  v_ini_ant date;
  v_fim_ant date;
  v_dias int;

  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  result jsonb;
begin
  perform bi_check_access(p_id_emp);

  if p_period not in ('mes', 'mes_passado', 'semestre', 'ano') then
    raise exception 'período inválido: %', p_period;
  end if;

  if p_period = 'mes' then
    v_ini := date_trunc('month', v_hoje)::date;
    v_fim := v_hoje + 1;
    v_dias := (v_hoje - v_ini) + 1;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '1 month')::date;
    v_fim_ant := v_ini_ant + v_dias;
  elsif p_period = 'mes_passado' then
    v_ini := (date_trunc('month', v_hoje) - interval '1 month')::date;
    v_fim := date_trunc('month', v_hoje)::date;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '2 month')::date;
    v_fim_ant := (date_trunc('month', v_hoje) - interval '1 month')::date;
  elsif p_period = 'semestre' then
    v_ini := (date_trunc('month', v_hoje) - interval '5 month')::date;
    v_fim := v_hoje + 1;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '11 month')::date;
    v_fim_ant := (date_trunc('month', v_hoje) - interval '5 month')::date;
  else
    v_ini := date_trunc('year', v_hoje)::date;
    v_fim := v_hoje + 1;
    v_dias := (v_hoje - v_ini) + 1;
    v_ini_ant := (date_trunc('year', v_hoje) - interval '1 year')::date;
    v_fim_ant := v_ini_ant + v_dias;
  end if;

  v_ini_ts := v_ini::timestamp at time zone v_tz;
  v_fim_ts := v_fim::timestamp at time zone v_tz;
  v_ini_ant_ts := v_ini_ant::timestamp at time zone v_tz;
  v_fim_ant_ts := v_fim_ant::timestamp at time zone v_tz;

  with atual as (
    select a."PROF_AGD" as id_prof,
           coalesce(sum(p."VL_PGTO"), 0) as recebido,
           coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0) as repasse
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and a."PROF_AGD" is not null
        and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim
      group by a."PROF_AGD"
  ),
  anterior as (
    select a."PROF_AGD" as id_prof,
           coalesce(sum(p."VL_PGTO"), 0) as recebido
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and a."PROF_AGD" is not null
        and p."DT_PGTO" >= v_ini_ant and p."DT_PGTO" < v_fim_ant
      group by a."PROF_AGD"
  ),
  agd_atual as (
    select "PROF_AGD" as id_prof,
           count(*) filter (where "STATUS_AGD" = 'REALIZADA') as realizadas,
           count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
      from "AGENDAMENTO"
      where "ID_EMP" = p_id_emp and "PROF_AGD" is not null
        and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
      group by "PROF_AGD"
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', pr."ID_PROF",
      'nome', pr."NOME_PROF",
      'recebido', round(coalesce(at.recebido, 0), 2),
      'recebidoDeltaPct', case when coalesce(an.recebido, 0) = 0 then null
                           else round((coalesce(at.recebido, 0) - an.recebido) / an.recebido * 100, 1) end,
      'repasseClinica', round(coalesce(at.repasse, 0), 2),
      'liquidoProf', round(coalesce(at.recebido, 0) - coalesce(at.repasse, 0), 2),
      'ticketMedio', case when coalesce(ag.realizadas, 0) = 0 then 0
                      else round(coalesce(at.recebido, 0) / ag.realizadas, 2) end,
      'realizadas', coalesce(ag.realizadas, 0),
      'faltas', coalesce(ag.faltas, 0),
      'taxaFaltaPct', case when (coalesce(ag.realizadas, 0) + coalesce(ag.faltas, 0)) = 0 then null
                       else round(coalesce(ag.faltas, 0)::numeric / (coalesce(ag.realizadas, 0) + coalesce(ag.faltas, 0)) * 100, 1) end
    ) order by coalesce(at.recebido, 0) desc
  ), '[]'::jsonb)
  into result
  from "PROFISSIONAL" pr
  left join atual at on at.id_prof = pr."ID_PROF"
  left join anterior an on an.id_prof = pr."ID_PROF"
  left join agd_atual ag on ag.id_prof = pr."ID_PROF"
  where pr."ID_EMP" = p_id_emp and pr."ATIVO_PROF" is true;

  return jsonb_build_object('profissionais', result);
end;
$$;
