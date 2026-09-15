-- RPCs do Vitta BI para a tela de Pacientes (bi/pages/pacientes.html), Fases 4
-- e 5 do plano em bi/PLANO_BI_PACIENTES.md (valor/LTV/Pareto, RFM + funil de
-- ciclo de vida, e complementos clínicos + cross-sell). Mesma regra
-- inegociável das demais RPCs do BI: nunca consulta direta às tabelas
-- transacionais nem filtro client-side de empresa — todo cálculo passa por
-- bi_check_access(p_id_emp) antes de ler qualquer linha. As três usam o
-- histórico completo do paciente (não seguem o filtro de período do topo da
-- página), igual às Fases 2 e 3.

-- Fase 4 (parte 1) — Valor: LTV médio, ticket médio por visita x por
-- paciente, top 15 pacientes por receita e curva de Pareto (10 decis).
create or replace function public.bi_pacientes_valor(
  p_id_emp uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  perform bi_check_access(p_id_emp);

  with pagto as (
    select "ID_PAC", "VL_PGTO"
      from "PAGAMENTO"
      where "ID_EMP" = p_id_emp and coalesce("ESTORNADO_PGTO", false) = false
  ),
  por_paciente as (
    select pg."ID_PAC", pac."NOME_PAC" as nome_pac, sum(pg."VL_PGTO") as total_pago, count(*) as n_pagamentos
      from pagto pg
      join "PACIENTE" pac on pac."ID_PAC" = pg."ID_PAC"
      group by pg."ID_PAC", pac."NOME_PAC"
  ),
  resumo as (
    select
      round(avg(total_pago), 2) as ltv_medio,
      (select round(avg("VL_PGTO"), 2) from pagto) as ticket_visita,
      count(*) as n_pacientes_pagantes,
      sum(total_pago) as receita_total
    from por_paciente
  ),
  top_pacientes as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'nome', nome_pac, 'totalPago', total_pago, 'numPagamentos', n_pagamentos
    ) order by total_pago desc), '[]'::jsonb) as v
    from (select nome_pac, total_pago, n_pagamentos from por_paciente order by total_pago desc limit 15) t
  ),
  pareto_calc as (
    select total_pago,
           row_number() over (order by total_pago desc) as rn,
           count(*) over () as n_total,
           sum(total_pago) over (order by total_pago desc rows between unbounded preceding and current row) as cum_receita,
           sum(total_pago) over () as receita_total
      from por_paciente
  ),
  pareto_dec as (
    select *, least(10, ceil(rn::numeric / nullif(n_total, 0) * 10)::int) as decile
      from pareto_calc
  ),
  pareto_pontos as (
    select decile,
           round(max(rn)::numeric / nullif(max(n_total), 0) * 100, 1) as pct_pacientes,
           round(max(cum_receita) / nullif(max(receita_total), 0) * 100, 1) as pct_receita
      from pareto_dec
      group by decile
  ),
  pareto_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'pctPacientes', pct_pacientes, 'pctReceita', pct_receita
    ) order by decile), '[]'::jsonb) as v
    from pareto_pontos
  )
  select jsonb_build_object(
    'ltvMedio', r.ltv_medio,
    'ticketMedioVisita', r.ticket_visita,
    'ticketMedioPaciente', r.ltv_medio,
    'nPacientesPagantes', r.n_pacientes_pagantes,
    'receitaTotal', r.receita_total,
    'topPacientes', tp.v,
    'pareto', pj.v,
    'pctReceitaTop20', (select pct_receita from pareto_pontos where decile = 2)
  )
  into v_result
  from resumo r, top_pacientes tp, pareto_json pj;

  return v_result;
end;
$function$;

-- Fase 4 (parte 2) — Ciclo de vida: segmentação RFM (recência = dias desde a
-- última consulta; frequência = nº de consultas; valor = total pago) em 6
-- segmentos fixos, e funil Lead → Paciente → Recorrente → Fiel → Perdido.
-- Regra de segmentação (determinística, sem thresholds no plano original):
--   recência > 180 dias        -> Perdidos
--   recência > 90 dias         -> Em risco
--   recência <= 90, 1 consulta -> Novos
--   recência <= 90, 2-3        -> Ocasionais
--   recência <= 90, 4+, valor no top 25% (entre os elegíveis) -> Campeões
--   recência <= 90, 4+, resto  -> Fiéis
-- "Perdido" no funil reaproveita o mesmo corte de 180 dias do RFM (é um
-- status, não um degrau sequencial do funil — paciente pode virar "perdido"
-- em qualquer estágio de recorrência).
create or replace function public.bi_pacientes_ciclo_vida(
  p_id_emp uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  perform bi_check_access(p_id_emp);

  with consulta_stats as (
    select c."ID_PAC", count(*) as n_consultas, max(c."DT_CONS") as ultima_consulta
      from "CONSULTA" c
      where c."ID_EMP" = p_id_emp
      group by c."ID_PAC"
  ),
  valor_stats as (
    select "ID_PAC", sum("VL_PGTO") as total_pago
      from "PAGAMENTO"
      where "ID_EMP" = p_id_emp and coalesce("ESTORNADO_PGTO", false) = false
      group by "ID_PAC"
  ),
  base as (
    select cs."ID_PAC", cs.n_consultas,
           extract(epoch from (now() - cs.ultima_consulta)) / 86400.0 as recencia_dias,
           coalesce(vs.total_pago, 0) as valor
      from consulta_stats cs
      left join valor_stats vs on vs."ID_PAC" = cs."ID_PAC"
  ),
  p75_valor as (
    select percentile_cont(0.75) within group (order by valor) as p75
      from base
      where n_consultas >= 4 and recencia_dias <= 90
  ),
  segmentado as (
    select b.*,
      case
        when b.recencia_dias > 180 then 'Perdidos'
        when b.recencia_dias > 90 then 'Em risco'
        when b.n_consultas = 1 then 'Novos'
        when b.n_consultas <= 3 then 'Ocasionais'
        when b.valor >= coalesce((select p75 from p75_valor), 0) then 'Campeões'
        else 'Fiéis'
      end as segmento
    from base b
  ),
  segmentos_agg as (
    select segmento, count(*) as total, round(avg(valor), 2) as valor_medio
      from segmentado
      group by segmento
  ),
  segmentos_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'nome', segmento, 'total', total, 'valorMedio', valor_medio
    ) order by case segmento
        when 'Campeões' then 1 when 'Fiéis' then 2 when 'Novos' then 3
        when 'Ocasionais' then 4 when 'Em risco' then 5 when 'Perdidos' then 6 else 7 end
    ), '[]'::jsonb) as v
    from segmentos_agg
  ),
  funil as (
    select
      (select count(*) from "LEADS" where "ID_EMP" = p_id_emp) as leads,
      (select count(*) from consulta_stats) as pacientes,
      (select count(*) from consulta_stats where n_consultas >= 2) as recorrentes,
      (select count(*) from consulta_stats where n_consultas >= 3) as fieis,
      (select count(*) from segmentado where segmento = 'Perdidos') as perdidos
  )
  select jsonb_build_object(
    'rfm', sj.v,
    'funil', jsonb_build_object(
      'leads', f.leads, 'pacientes', f.pacientes, 'recorrentes', f.recorrentes,
      'fieis', f.fieis, 'perdidos', f.perdidos
    )
  )
  into v_result
  from segmentos_json sj, funil f;

  return v_result;
end;
$function$;

-- Fase 5 — Complementos clínicos: % com alergia ativa, % de agendamentos
-- REALIZADA com sinais vitais registrados, top 10 diagnósticos (CID),
-- rascunho x finalizadas, e cross-sell (% atendidos por 2+ especialidades
-- via CONSULTA x PROFISSIONAL.ID_ESPEC, e especialidade "porta de entrada"
-- mais comum entre quem passou por 2+ especialidades).
create or replace function public.bi_pacientes_clinico(
  p_id_emp uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  perform bi_check_access(p_id_emp);

  with ativos as (
    select "ID_PAC" from "PACIENTE" where "EMP_PAC" = p_id_emp and "ATIVO_PAC" = true
  ),
  com_alergia as (
    select distinct a."ID_PAC"
      from "ALERGIA" a
      join ativos on ativos."ID_PAC" = a."ID_PAC"
      where a."ID_EMP" = p_id_emp and coalesce(a."ATIVO_ALERGIA", true) = true
  ),
  agd_realizados as (
    select "ID_AGD" from "AGENDAMENTO" where "ID_EMP" = p_id_emp and "STATUS_AGD" = 'REALIZADA'
  ),
  agd_com_sv as (
    select distinct sv."ID_AGD"
      from "SINAL_VITAL" sv
      join agd_realizados ar on ar."ID_AGD" = sv."ID_AGD"
      where sv."ID_EMP" = p_id_emp
  ),
  consultas as (
    select "ID_CONS", "DT_CONS", "CID_CONS", "RASCUNHO", "ID_PAC", "ID_PROF"
      from "CONSULTA"
      where "ID_EMP" = p_id_emp
  ),
  diagnosticos as (
    select coalesce(jsonb_agg(jsonb_build_object('cid', cid, 'total', total) order by total desc), '[]'::jsonb) as v
      from (
        select "CID_CONS" as cid, count(*) as total
          from consultas
          where "CID_CONS" is not null and btrim("CID_CONS") <> ''
          group by "CID_CONS"
          order by count(*) desc
          limit 10
      ) t
  ),
  rascunho_stats as (
    select count(*) filter (where "RASCUNHO" = true) as rascunho,
           count(*) filter (where coalesce("RASCUNHO", false) = false) as finalizadas
      from consultas
  ),
  especialidade_por_prof as (
    select p."ID_PROF", e."NOME_ESPEC" as especialidade
      from "PROFISSIONAL" p
      left join "ESPECIALIDADE" e on e."ID_ESPEC" = p."ID_ESPEC"
      where p."ID_EMP" = p_id_emp
  ),
  consulta_espec as (
    select c."ID_PAC", c."DT_CONS", ep.especialidade
      from consultas c
      join especialidade_por_prof ep on ep."ID_PROF" = c."ID_PROF"
      where ep.especialidade is not null
  ),
  pac_especialidades as (
    select "ID_PAC", count(distinct especialidade) as n_espec
      from consulta_espec
      group by "ID_PAC"
  ),
  cross_sell_stats as (
    select count(*) as total_pacientes, count(*) filter (where n_espec >= 2) as multi_espec
      from pac_especialidades
  ),
  porta_entrada as (
    select especialidade, count(*) as total
      from (
        select distinct on (ce."ID_PAC") ce."ID_PAC", ce.especialidade
          from consulta_espec ce
          join pac_especialidades pe on pe."ID_PAC" = ce."ID_PAC" and pe.n_espec >= 2
          order by ce."ID_PAC", ce."DT_CONS" asc
      ) primeira
      group by especialidade
      order by count(*) desc
      limit 8
  ),
  porta_entrada_json as (
    select coalesce(jsonb_agg(jsonb_build_object('especialidade', especialidade, 'total', total) order by total desc), '[]'::jsonb) as v
      from porta_entrada
  ),
  resumo as (
    select
      (select count(*) from ativos) as total_ativos,
      (select count(*) from com_alergia) as total_alergia,
      (select count(*) from agd_realizados) as total_agd,
      (select count(*) from agd_com_sv) as total_agd_sv,
      (select rascunho from rascunho_stats) as rascunho,
      (select finalizadas from rascunho_stats) as finalizadas,
      (select total_pacientes from cross_sell_stats) as cs_total,
      (select multi_espec from cross_sell_stats) as cs_multi
  )
  select jsonb_build_object(
    'totalAtivos', r.total_ativos,
    'totalComAlergia', r.total_alergia,
    'pctComAlergia', case when r.total_ativos = 0 then null else round(r.total_alergia::numeric / r.total_ativos * 100, 1) end,
    'totalAgendamentosRealizados', r.total_agd,
    'totalComSinaisVitais', r.total_agd_sv,
    'pctComSinaisVitais', case when r.total_agd = 0 then null else round(r.total_agd_sv::numeric / r.total_agd * 100, 1) end,
    'diagnosticosComuns', d.v,
    'consultasFinalizadas', r.finalizadas,
    'consultasRascunho', r.rascunho,
    'pctRascunho', case when (r.finalizadas + r.rascunho) = 0 then null else round(r.rascunho::numeric / (r.finalizadas + r.rascunho) * 100, 1) end,
    'crossSell', jsonb_build_object(
      'totalPacientesComEspecialidade', r.cs_total,
      'totalMultiEspecialidade', r.cs_multi,
      'pctMultiEspecialidade', case when r.cs_total = 0 then null else round(r.cs_multi::numeric / r.cs_total * 100, 1) end,
      'portaEntrada', pe.v
    )
  )
  into v_result
  from resumo r, diagnosticos d, porta_entrada_json pe;

  return v_result;
end;
$function$;
