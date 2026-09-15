-- 1. bi_equipe_resumo — KPIs de topo (Fase 1)
create or replace function public.bi_equipe_resumo(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_ini date; v_fim date; v_ini_ant date; v_fim_ant date; v_dias int;
  v_ini_ts timestamptz; v_fim_ts timestamptz; v_ini_ant_ts timestamptz; v_fim_ant_ts timestamptz;
  v_profissionais_ativos bigint;
  v_receita numeric; v_receita_ant numeric;
  v_atendimentos bigint; v_atendimentos_ant bigint;
begin
  perform bi_check_access(p_id_emp);
  if p_period not in ('hoje','ontem','7dias','30dias','mes','mes_passado','trimestre','ano','custom') then
    raise exception 'período inválido: %', p_period;
  end if;
  if p_period = 'hoje' then
    v_ini := v_hoje; v_fim := v_hoje + 1; v_ini_ant := v_hoje - 1; v_fim_ant := v_hoje;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1; v_fim := v_hoje; v_ini_ant := v_hoje - 2; v_fim_ant := v_hoje - 1;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6; v_fim := v_hoje + 1; v_ini_ant := v_ini - 7; v_fim_ant := v_ini;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29; v_fim := v_hoje + 1; v_ini_ant := v_ini - 30; v_fim_ant := v_ini;
  elsif p_period = 'mes' then
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
  elsif p_period = 'trimestre' then
    v_ini := (date_trunc('month', v_hoje) - interval '2 month')::date;
    v_fim := v_hoje + 1;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '5 month')::date;
    v_fim_ant := (date_trunc('month', v_hoje) - interval '2 month')::date;
  elsif p_period = 'ano' then
    v_ini := date_trunc('year', v_hoje)::date;
    v_fim := v_hoje + 1;
    v_dias := (v_hoje - v_ini) + 1;
    v_ini_ant := (date_trunc('year', v_hoje) - interval '1 year')::date;
    v_fim_ant := v_ini_ant + v_dias;
  else
    if p_data_ini is null or p_data_fim is null or p_data_fim < p_data_ini then
      raise exception 'período customizado inválido: informe p_data_ini e p_data_fim';
    end if;
    v_ini := p_data_ini;
    v_fim := p_data_fim + 1;
    v_dias := v_fim - v_ini;
    v_ini_ant := v_ini - v_dias;
    v_fim_ant := v_ini;
  end if;
  v_ini_ts := v_ini::timestamp at time zone v_tz;
  v_fim_ts := v_fim::timestamp at time zone v_tz;
  v_ini_ant_ts := v_ini_ant::timestamp at time zone v_tz;
  v_fim_ant_ts := v_fim_ant::timestamp at time zone v_tz;

  select count(*) into v_profissionais_ativos
  from "PROFISSIONAL" where "ID_EMP" = p_id_emp and "ATIVO_PROF" is true;

  select coalesce(sum(p."VL_PGTO"), 0) into v_receita
  from "PAGAMENTO" p
  inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
  where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
    and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim;

  select coalesce(sum(p."VL_PGTO"), 0) into v_receita_ant
  from "PAGAMENTO" p
  inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
  where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
    and p."DT_PGTO" >= v_ini_ant and p."DT_PGTO" < v_fim_ant;

  select count(*) filter (where "STATUS_AGD" = 'REALIZADA') into v_atendimentos
  from "AGENDAMENTO" where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts;

  select count(*) filter (where "STATUS_AGD" = 'REALIZADA') into v_atendimentos_ant
  from "AGENDAMENTO" where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ant_ts and "DT_AGD" < v_fim_ant_ts;

  return jsonb_build_object(
    'profissionaisAtivos', v_profissionais_ativos,
    'receitaTotal', v_receita,
    'receitaTotalDeltaPct', case when v_receita_ant = 0 then null else round((v_receita - v_receita_ant) / v_receita_ant * 100, 1) end,
    'totalAtendimentos', v_atendimentos,
    'totalAtendimentosDeltaPct', case when v_atendimentos_ant = 0 then null else round((v_atendimentos - v_atendimentos_ant)::numeric / v_atendimentos_ant * 100, 1) end
  );
end;
$function$;

-- 2. bi_equipe_por_profissional — ranking completo (Fase 1 itens 2-3, Fase 2, Fase 3 item 6, Fase 4)
create or replace function public.bi_equipe_por_profissional(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_ini date; v_fim date; v_ini_ant date; v_fim_ant date; v_dias int;
  v_ini_ts timestamptz; v_fim_ts timestamptz; v_ini_ant_ts timestamptz; v_fim_ant_ts timestamptz;
  v_result jsonb;
begin
  perform bi_check_access(p_id_emp);
  if p_period not in ('hoje','ontem','7dias','30dias','mes','mes_passado','trimestre','ano','custom') then
    raise exception 'período inválido: %', p_period;
  end if;
  if p_period = 'hoje' then
    v_ini := v_hoje; v_fim := v_hoje + 1; v_ini_ant := v_hoje - 1; v_fim_ant := v_hoje;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1; v_fim := v_hoje; v_ini_ant := v_hoje - 2; v_fim_ant := v_hoje - 1;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6; v_fim := v_hoje + 1; v_ini_ant := v_ini - 7; v_fim_ant := v_ini;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29; v_fim := v_hoje + 1; v_ini_ant := v_ini - 30; v_fim_ant := v_ini;
  elsif p_period = 'mes' then
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
  elsif p_period = 'trimestre' then
    v_ini := (date_trunc('month', v_hoje) - interval '2 month')::date;
    v_fim := v_hoje + 1;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '5 month')::date;
    v_fim_ant := (date_trunc('month', v_hoje) - interval '2 month')::date;
  elsif p_period = 'ano' then
    v_ini := date_trunc('year', v_hoje)::date;
    v_fim := v_hoje + 1;
    v_dias := (v_hoje - v_ini) + 1;
    v_ini_ant := (date_trunc('year', v_hoje) - interval '1 year')::date;
    v_fim_ant := v_ini_ant + v_dias;
  else
    if p_data_ini is null or p_data_fim is null or p_data_fim < p_data_ini then
      raise exception 'período customizado inválido: informe p_data_ini e p_data_fim';
    end if;
    v_ini := p_data_ini;
    v_fim := p_data_fim + 1;
    v_dias := v_fim - v_ini;
    v_ini_ant := v_ini - v_dias;
    v_fim_ant := v_ini;
  end if;
  v_ini_ts := v_ini::timestamp at time zone v_tz;
  v_fim_ts := v_fim::timestamp at time zone v_tz;
  v_ini_ant_ts := v_ini_ant::timestamp at time zone v_tz;
  v_fim_ant_ts := v_fim_ant::timestamp at time zone v_tz;

  with pagamentos_periodo as (
    select a."PROF_AGD" as id_prof, sum(p."VL_PGTO") as receita
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and a."PROF_AGD" is not null
      and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim
    group by a."PROF_AGD"
  ),
  agd_periodo as (
    select "PROF_AGD" as id_prof,
      count(*) as total,
      count(*) filter (where "STATUS_AGD" = 'REALIZADA') as realizadas,
      count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "PROF_AGD" is not null
      and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
    group by "PROF_AGD"
  ),
  consultas_periodo as (
    select "ID_PROF" as id_prof,
      count(*) as total,
      count(*) filter (where "RASCUNHO" is true) as rascunhos
    from "CONSULTA"
    where "ID_EMP" = p_id_emp and "ID_PROF" is not null
      and "DT_CONS" >= v_ini_ts and "DT_CONS" < v_fim_ts
    group by "ID_PROF"
  ),
  leads_periodo as (
    select "ID_PROF" as id_prof,
      count(*) as total,
      count(*) filter (where "FOI_AGENDADO_LEAD" is true) as agendados,
      count(*) filter (where "DESISTENCIA_LEAD" is not null) as desistencias
    from "LEADS"
    where "ID_EMP" = p_id_emp and "ID_PROF" is not null
      and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts
    group by "ID_PROF"
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'idProf', pr."ID_PROF",
    'nome', pr."NOME_PROF",
    'especialidade', pr."ESPECIAL_PROF",
    'receita', round(coalesce(pg.receita, 0), 2),
    'percClinica', coalesce(pr."PERC_PROF", 0),
    'comissaoEstimada', round(coalesce(pg.receita, 0) * (1 - coalesce(pr."PERC_PROF", 0) / 100.0), 2),
    'atendimentosRealizados', coalesce(ag.realizadas, 0),
    'faltas', coalesce(ag.faltas, 0),
    'taxaRealizacaoPct', case when coalesce(ag.total, 0) = 0 then null else round(coalesce(ag.realizadas, 0)::numeric / ag.total * 100, 1) end,
    'taxaFaltaPct', case when coalesce(ag.total, 0) = 0 then null else round(coalesce(ag.faltas, 0)::numeric / ag.total * 100, 1) end,
    'ticketMedio', case when coalesce(ag.realizadas, 0) = 0 then 0 else round(coalesce(pg.receita, 0) / ag.realizadas, 2) end,
    'consultasRegistradas', coalesce(cs.total, 0),
    'pctRascunho', case when coalesce(cs.total, 0) = 0 then null else round(coalesce(cs.rascunhos, 0)::numeric / cs.total * 100, 1) end,
    'pctConsultaRegistrada', case when coalesce(ag.realizadas, 0) = 0 then null else round(coalesce(cs.total, 0)::numeric / ag.realizadas * 100, 1) end,
    'leadsTotal', coalesce(ld.total, 0),
    'leadsConversaoPct', case when coalesce(ld.total, 0) = 0 then null else round(coalesce(ld.agendados, 0)::numeric / ld.total * 100, 1) end,
    'leadsDesistenciaPct', case when coalesce(ld.total, 0) = 0 then null else round(coalesce(ld.desistencias, 0)::numeric / ld.total * 100, 1) end
  ) order by coalesce(pg.receita, 0) desc, pr."NOME_PROF"), '[]'::jsonb)
  into v_result
  from "PROFISSIONAL" pr
  left join pagamentos_periodo pg on pg.id_prof = pr."ID_PROF"
  left join agd_periodo ag on ag.id_prof = pr."ID_PROF"
  left join consultas_periodo cs on cs.id_prof = pr."ID_PROF"
  left join leads_periodo ld on ld.id_prof = pr."ID_PROF"
  where pr."ID_EMP" = p_id_emp and pr."ATIVO_PROF" is true;

  return jsonb_build_object('profissionais', v_result);
end;
$function$;

-- 3. bi_equipe_especialidade — produtividade por especialidade (Fase 3 item 7)
create or replace function public.bi_equipe_especialidade(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_ini date; v_fim date; v_ini_ant date; v_fim_ant date; v_dias int;
  v_ini_ts timestamptz; v_fim_ts timestamptz; v_ini_ant_ts timestamptz; v_fim_ant_ts timestamptz;
  v_result jsonb;
begin
  perform bi_check_access(p_id_emp);
  if p_period not in ('hoje','ontem','7dias','30dias','mes','mes_passado','trimestre','ano','custom') then
    raise exception 'período inválido: %', p_period;
  end if;
  if p_period = 'hoje' then
    v_ini := v_hoje; v_fim := v_hoje + 1; v_ini_ant := v_hoje - 1; v_fim_ant := v_hoje;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1; v_fim := v_hoje; v_ini_ant := v_hoje - 2; v_fim_ant := v_hoje - 1;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6; v_fim := v_hoje + 1; v_ini_ant := v_ini - 7; v_fim_ant := v_ini;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29; v_fim := v_hoje + 1; v_ini_ant := v_ini - 30; v_fim_ant := v_ini;
  elsif p_period = 'mes' then
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
  elsif p_period = 'trimestre' then
    v_ini := (date_trunc('month', v_hoje) - interval '2 month')::date;
    v_fim := v_hoje + 1;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '5 month')::date;
    v_fim_ant := (date_trunc('month', v_hoje) - interval '2 month')::date;
  elsif p_period = 'ano' then
    v_ini := date_trunc('year', v_hoje)::date;
    v_fim := v_hoje + 1;
    v_dias := (v_hoje - v_ini) + 1;
    v_ini_ant := (date_trunc('year', v_hoje) - interval '1 year')::date;
    v_fim_ant := v_ini_ant + v_dias;
  else
    if p_data_ini is null or p_data_fim is null or p_data_fim < p_data_ini then
      raise exception 'período customizado inválido: informe p_data_ini e p_data_fim';
    end if;
    v_ini := p_data_ini;
    v_fim := p_data_fim + 1;
    v_dias := v_fim - v_ini;
    v_ini_ant := v_ini - v_dias;
    v_fim_ant := v_ini;
  end if;
  v_ini_ts := v_ini::timestamp at time zone v_tz;
  v_fim_ts := v_fim::timestamp at time zone v_tz;
  v_ini_ant_ts := v_ini_ant::timestamp at time zone v_tz;
  v_fim_ant_ts := v_fim_ant::timestamp at time zone v_tz;

  with pagamentos_periodo as (
    select a."PROF_AGD" as id_prof, sum(p."VL_PGTO") as receita
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and a."PROF_AGD" is not null
      and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim
    group by a."PROF_AGD"
  ),
  agd_periodo as (
    select "PROF_AGD" as id_prof, count(*) filter (where "STATUS_AGD" = 'REALIZADA') as realizadas
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "PROF_AGD" is not null
      and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
    group by "PROF_AGD"
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'nome', especialidade, 'receita', receita, 'atendimentos', atendimentos
  ) order by receita desc), '[]'::jsonb)
  into v_result
  from (
    select coalesce(pr."ESPECIAL_PROF", 'Não informado') as especialidade,
      round(coalesce(sum(pg.receita), 0), 2) as receita,
      coalesce(sum(ag.realizadas), 0) as atendimentos
    from "PROFISSIONAL" pr
    left join pagamentos_periodo pg on pg.id_prof = pr."ID_PROF"
    left join agd_periodo ag on ag.id_prof = pr."ID_PROF"
    where pr."ID_EMP" = p_id_emp
    group by 1
  ) t;

  return jsonb_build_object('porEspecialidade', v_result);
end;
$function$;

-- 4. bi_equipe_evolucao — evolução mensal de receita por profissional, top 5 (Fase 3 item 8)
-- Não segue o filtro de período do topo: sempre ano corrente (jan..mês atual),
-- mesmo padrão já usado em bi_leads_por_dimensao.evolucaoMensal.
create or replace function public.bi_equipe_evolucao(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_ano int := extract(year from v_hoje)::int;
  v_mes_atual int := extract(month from v_hoje)::int;
  v_top jsonb;
begin
  perform bi_check_access(p_id_emp);

  with pagamentos_ano as (
    select a."PROF_AGD" as id_prof,
      extract(month from p."DT_PGTO")::int as mes,
      sum(p."VL_PGTO") as receita
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and a."PROF_AGD" is not null
      and p."DT_PGTO" >= make_date(v_ano, 1, 1) and p."DT_PGTO" < make_date(v_ano + 1, 1, 1)
    group by 1, 2
  ),
  top5 as (
    select id_prof, sum(receita) as total
    from pagamentos_ano
    group by id_prof
    order by total desc
    limit 5
  ),
  meses as (
    select generate_series(1, v_mes_atual) as mes
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'idProf', t.id_prof,
    'nome', pr."NOME_PROF",
    'total', round(t.total, 2),
    'serie', (
      select coalesce(jsonb_agg(jsonb_build_object('mes', m.mes, 'receita', round(coalesce(pa.receita, 0), 2)) order by m.mes), '[]'::jsonb)
      from meses m
      left join pagamentos_ano pa on pa.id_prof = t.id_prof and pa.mes = m.mes
    )
  ) order by t.total desc), '[]'::jsonb)
  into v_top
  from top5 t
  inner join "PROFISSIONAL" pr on pr."ID_PROF" = t.id_prof;

  return jsonb_build_object('ano', v_ano, 'mesAtual', v_mes_atual, 'profissionais', v_top);
end;
$function$;
