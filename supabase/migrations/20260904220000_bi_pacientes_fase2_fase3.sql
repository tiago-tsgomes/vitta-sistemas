-- RPCs do Vitta BI para a tela de Pacientes (bi/pages/pacientes.html), Fases 2
-- e 3 do plano em bi/PLANO_BI_PACIENTES.md (frequência/esporadicidade e
-- rotatividade/retenção). Mesma regra inegociável das demais RPCs do BI:
-- nunca consulta direta às tabelas transacionais nem filtro client-side de
-- empresa — todo cálculo passa por bi_check_access(p_id_emp) antes de ler
-- qualquer linha. Ambas usam o histórico completo do paciente (não seguem o
-- filtro de período do topo da página, igual à evolução mensal e às
-- quebras demográficas de bi_pacientes_por_dimensao).

-- Fase 2 — Frequência e esporadicidade: intervalo médio entre consultas por
-- paciente (CONSULTA.DT_CONS via lag()), % que só vieram 1x, desvio-padrão
-- médio do intervalo (indicador de esporadicidade) e distribuição em faixas
-- de frequência.
create or replace function public.bi_pacientes_frequencia(
  p_id_emp uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_pacientes_com_historico bigint;
  v_intervalo_medio numeric;
  v_pct_so_uma numeric;
  v_desvio_medio numeric;
  v_distribuicao jsonb;
begin
  perform bi_check_access(p_id_emp);

  with consultas as (
    select c."ID_PAC", c."DT_CONS",
           lag(c."DT_CONS") over (partition by c."ID_PAC" order by c."DT_CONS") as anterior
      from "CONSULTA" c
      where c."ID_EMP" = p_id_emp
  ),
  intervalos as (
    select "ID_PAC", extract(epoch from ("DT_CONS" - anterior)) / 86400.0 as dias
      from consultas
      where anterior is not null
  ),
  por_paciente as (
    select "ID_PAC", avg(dias) as intervalo_medio, stddev(dias) as desvio, count(*) as n_intervalos
      from intervalos
      group by "ID_PAC"
  ),
  total_consultas as (
    select "ID_PAC", count(*) as n_consultas
      from "CONSULTA"
      where "ID_EMP" = p_id_emp
      group by "ID_PAC"
  )
  select
    count(*),
    round(avg(pp.intervalo_medio), 1),
    round(count(*) filter (where tc.n_consultas = 1)::numeric / nullif(count(*), 0) * 100, 1),
    round(avg(pp.desvio) filter (where pp.n_intervalos >= 2), 1)
  into v_pacientes_com_historico, v_intervalo_medio, v_pct_so_uma, v_desvio_medio
  from total_consultas tc
  left join por_paciente pp on pp."ID_PAC" = tc."ID_PAC";

  with total_consultas as (
    select "ID_PAC", count(*) as n_consultas
      from "CONSULTA"
      where "ID_EMP" = p_id_emp
      group by "ID_PAC"
  ),
  por_paciente as (
    with consultas as (
      select c."ID_PAC", c."DT_CONS",
             lag(c."DT_CONS") over (partition by c."ID_PAC" order by c."DT_CONS") as anterior
        from "CONSULTA" c
        where c."ID_EMP" = p_id_emp
    )
    select "ID_PAC", avg(extract(epoch from ("DT_CONS" - anterior)) / 86400.0) as intervalo_medio
      from consultas
      where anterior is not null
      group by "ID_PAC"
  ),
  faixas as (
    select tc."ID_PAC",
           case
             when tc.n_consultas = 1 then 'Só 1 consulta'
             when pp.intervalo_medio <= 10 then 'Semanal'
             when pp.intervalo_medio <= 20 then 'Quinzenal'
             when pp.intervalo_medio <= 45 then 'Mensal'
             else 'Esporádico'
           end as faixa,
           case
             when tc.n_consultas = 1 then 1
             when pp.intervalo_medio <= 10 then 2
             when pp.intervalo_medio <= 20 then 3
             when pp.intervalo_medio <= 45 then 4
             else 5
           end as ordem
      from total_consultas tc
      left join por_paciente pp on pp."ID_PAC" = tc."ID_PAC"
  )
  select coalesce(jsonb_agg(jsonb_build_object('nome', faixa, 'total', total) order by ordem), '[]'::jsonb)
    into v_distribuicao
    from (select faixa, ordem, count(*) as total from faixas group by faixa, ordem) t;

  return jsonb_build_object(
    'pacientesComHistorico', v_pacientes_com_historico,
    'intervaloMedioDias', v_intervalo_medio,
    'pctSoUmaConsulta', v_pct_so_uma,
    'desvioPadraoMedioDias', v_desvio_medio,
    'distribuicaoFrequencia', v_distribuicao
  );
end;
$function$;

-- Fase 3 — Rotatividade e retenção: pacientes sem retorno há mais de
-- p_dias_sem_retorno dias (churn "pontual", baseado na última visita
-- REALIZADA em AGENDAMENTO), churn mensal + crescimento líquido no ano
-- corrente, e curva de retenção por coorte (mês de cadastro x meses
-- seguintes, % que teve ao menos 1 agendamento REALIZADA).
create or replace function public.bi_pacientes_rotatividade(
  p_id_emp uuid,
  p_dias_sem_retorno int default 90
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_ano int := extract(year from v_hoje)::int;
  v_mes_atual int := extract(month from v_hoje)::int;
  v_result jsonb;
begin
  perform bi_check_access(p_id_emp);

  if p_dias_sem_retorno is null or p_dias_sem_retorno < 1 then
    raise exception 'p_dias_sem_retorno inválido: %', p_dias_sem_retorno;
  end if;

  -- churn_calc: última visita REALIZADA por paciente (AGENDAMENTO) e data em
  -- que o paciente "cruzou" o limite de dias sem retorno (baseline = última
  -- visita, ou a data de cadastro para quem nunca teve uma visita realizada).
  with churn_calc as (
    select p."ID_PAC", p."DTCRI_PAC",
           (select max(a."DT_AGD") from "AGENDAMENTO" a
              where a."PAC_AGD" = p."ID_PAC" and a."ID_EMP" = p_id_emp and a."STATUS_AGD" = 'REALIZADA') as ultima_visita
      from "PACIENTE" p
      where p."EMP_PAC" = p_id_emp
  ),
  churn_date_calc as (
    select "ID_PAC", "DTCRI_PAC",
           coalesce((ultima_visita at time zone v_tz)::date, ("DTCRI_PAC" at time zone v_tz)::date) + p_dias_sem_retorno as churn_date
      from churn_calc
  ),
  totais as (
    select count(*) as total, count(*) filter (where churn_date <= v_hoje) as perdidos
      from churn_date_calc
  ),
  meses as (
    select generate_series(1, v_mes_atual) as mes
  ),
  churn_mensal_calc as (
    select m.mes,
           (select count(*) from churn_date_calc t
              where (t."DTCRI_PAC" at time zone v_tz)::date < make_date(v_ano, m.mes, 1)
                and t.churn_date >= make_date(v_ano, m.mes, 1)) as base_ativos,
           (select count(*) from churn_date_calc t
              where t.churn_date <= v_hoje
                and extract(year from t.churn_date)::int = v_ano
                and extract(month from t.churn_date)::int = m.mes) as perdidos,
           (select count(*) from "PACIENTE" p
              where p."EMP_PAC" = p_id_emp
                and extract(year from (p."DTCRI_PAC" at time zone v_tz))::int = v_ano
                and extract(month from (p."DTCRI_PAC" at time zone v_tz))::int = m.mes) as novos
      from meses m
  ),
  churn_mensal_json as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'mes', mes,
        'baseAtivos', base_ativos,
        'perdidos', perdidos,
        'churnPct', case when base_ativos = 0 then null else round(perdidos::numeric / base_ativos * 100, 1) end,
        'novos', novos,
        'crescimentoLiquido', novos - perdidos
      ) order by mes
    ), '[]'::jsonb) as v
      from churn_mensal_calc
  ),
  -- curva de retenção por coorte: coortes = mês de cadastro no ano corrente,
  -- pontos = % da coorte com ao menos 1 agendamento REALIZADA em cada mês
  -- seguinte (até 5 meses depois, limitado ao mês atual).
  cohort_size as (
    select extract(month from (p."DTCRI_PAC" at time zone v_tz))::int as cmes, count(*) as tamanho
      from "PACIENTE" p
      where p."EMP_PAC" = p_id_emp
        and extract(year from (p."DTCRI_PAC" at time zone v_tz))::int = v_ano
      group by 1
  ),
  offsets as (
    select generate_series(0, 5) as k
  ),
  cohort_offsets as (
    select cs.cmes, cs.tamanho, o.k
      from cohort_size cs
      cross join offsets o
      where cs.cmes + o.k <= v_mes_atual
  ),
  retidos as (
    select co.cmes, co.k, co.tamanho,
           count(distinct p."ID_PAC") as retidos
      from cohort_offsets co
      join "PACIENTE" p
        on p."EMP_PAC" = p_id_emp
        and extract(year from (p."DTCRI_PAC" at time zone v_tz))::int = v_ano
        and extract(month from (p."DTCRI_PAC" at time zone v_tz))::int = co.cmes
      left join "AGENDAMENTO" a
        on a."PAC_AGD" = p."ID_PAC"
        and a."ID_EMP" = p_id_emp
        and a."STATUS_AGD" = 'REALIZADA'
        and extract(year from (a."DT_AGD" at time zone v_tz))::int = v_ano
        and extract(month from (a."DT_AGD" at time zone v_tz))::int = co.cmes + co.k
      group by co.cmes, co.k, co.tamanho
  ),
  por_cohort as (
    select cmes, max(tamanho) as tamanho,
           jsonb_agg(jsonb_build_object(
             'k', k,
             'pct', case when tamanho = 0 then null else round(coalesce(retidos, 0)::numeric / tamanho * 100, 1) end
           ) order by k) as pontos
      from retidos
      group by cmes
  ),
  retencao_json as (
    select coalesce(jsonb_agg(
      jsonb_build_object('mes', cmes, 'tamanho', tamanho, 'pontos', pontos) order by cmes
    ), '[]'::jsonb) as v
      from por_cohort
  )
  select jsonb_build_object(
    'diasSemRetorno', p_dias_sem_retorno,
    'totalPacientes', t.total,
    'pacientesPerdidos', t.perdidos,
    'pacientesPerdidosPct', case when t.total = 0 then null else round(t.perdidos::numeric / t.total * 100, 1) end,
    'churnMensal', cmj.v,
    'retencaoCoorte', rj.v
  )
  into v_result
  from totais t, churn_mensal_json cmj, retencao_json rj;

  return v_result;
end;
$function$;
