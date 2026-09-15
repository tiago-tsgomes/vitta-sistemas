-- ============================================================
-- Vitta BI — Agenda & Ocupação (Fase 1, 2, 3 e 4)
-- ============================================================

-- ============================================================
-- 1. bi_agenda_resumo — KPIs de topo (Fase 1) + Valor (Fase 4)
-- ============================================================
create or replace function public.bi_agenda_resumo(
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

  v_ini date;
  v_fim date;
  v_ini_ant date;
  v_fim_ant date;
  v_dias int;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  v_total bigint;
  v_total_ant bigint;
  v_realizadas bigint;
  v_realizadas_ant bigint;
  v_faltas bigint;
  v_faltas_ant bigint;
  v_recorrentes bigint;
  v_recorrentes_ant bigint;
  v_valor_previsto numeric;
  v_valor_previsto_ant numeric;
  v_valor_realizado numeric;
  v_valor_realizado_ant numeric;
  v_realizadas_sem_pgto bigint;
  v_realizadas_sem_pgto_ant bigint;
  v_perda_faltas numeric;
  v_perda_faltas_ant numeric;

  v_taxa_realizacao numeric;
  v_taxa_realizacao_ant numeric;
  v_taxa_falta numeric;
  v_taxa_falta_ant numeric;
  v_taxa_recorrentes numeric;
  v_taxa_recorrentes_ant numeric;
  v_aderencia numeric;
  v_aderencia_ant numeric;
  v_pct_sem_pgto numeric;
  v_pct_sem_pgto_ant numeric;
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

  select
    count(*),
    count(*) filter (where "STATUS_AGD" = 'REALIZADA'),
    count(*) filter (where "STATUS_AGD" = 'FALTA'),
    count(*) filter (where "ID_SERIE" is not null),
    coalesce(sum("VALOR_PREVISTO_AGD"), 0),
    coalesce(sum("VALOR_AGD") filter (where "STATUS_AGD" = 'REALIZADA'), 0),
    count(*) filter (where "STATUS_AGD" = 'REALIZADA' and "PGTO_AGD" is not true),
    coalesce(sum("VALOR_PREVISTO_AGD") filter (where "STATUS_AGD" = 'FALTA'), 0)
  into v_total, v_realizadas, v_faltas, v_recorrentes, v_valor_previsto, v_valor_realizado, v_realizadas_sem_pgto, v_perda_faltas
  from "AGENDAMENTO"
  where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts;

  select
    count(*),
    count(*) filter (where "STATUS_AGD" = 'REALIZADA'),
    count(*) filter (where "STATUS_AGD" = 'FALTA'),
    count(*) filter (where "ID_SERIE" is not null),
    coalesce(sum("VALOR_PREVISTO_AGD"), 0),
    coalesce(sum("VALOR_AGD") filter (where "STATUS_AGD" = 'REALIZADA'), 0),
    count(*) filter (where "STATUS_AGD" = 'REALIZADA' and "PGTO_AGD" is not true),
    coalesce(sum("VALOR_PREVISTO_AGD") filter (where "STATUS_AGD" = 'FALTA'), 0)
  into v_total_ant, v_realizadas_ant, v_faltas_ant, v_recorrentes_ant, v_valor_previsto_ant, v_valor_realizado_ant, v_realizadas_sem_pgto_ant, v_perda_faltas_ant
  from "AGENDAMENTO"
  where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ant_ts and "DT_AGD" < v_fim_ant_ts;

  v_taxa_realizacao := case when v_total = 0 then null else round(v_realizadas::numeric / v_total * 100, 1) end;
  v_taxa_realizacao_ant := case when v_total_ant = 0 then null else round(v_realizadas_ant::numeric / v_total_ant * 100, 1) end;

  v_taxa_falta := case when v_total = 0 then null else round(v_faltas::numeric / v_total * 100, 1) end;
  v_taxa_falta_ant := case when v_total_ant = 0 then null else round(v_faltas_ant::numeric / v_total_ant * 100, 1) end;

  v_taxa_recorrentes := case when v_total = 0 then null else round(v_recorrentes::numeric / v_total * 100, 1) end;
  v_taxa_recorrentes_ant := case when v_total_ant = 0 then null else round(v_recorrentes_ant::numeric / v_total_ant * 100, 1) end;

  v_aderencia := case when v_valor_previsto = 0 then null else round(v_valor_realizado / v_valor_previsto * 100, 1) end;
  v_aderencia_ant := case when v_valor_previsto_ant = 0 then null else round(v_valor_realizado_ant / v_valor_previsto_ant * 100, 1) end;

  v_pct_sem_pgto := case when v_realizadas = 0 then null else round(v_realizadas_sem_pgto::numeric / v_realizadas * 100, 1) end;
  v_pct_sem_pgto_ant := case when v_realizadas_ant = 0 then null else round(v_realizadas_sem_pgto_ant::numeric / v_realizadas_ant * 100, 1) end;

  return jsonb_build_object(
    'totalAgendamentos', v_total,
    'totalAgendamentosDeltaPct', case when v_total_ant = 0 then null else round((v_total - v_total_ant)::numeric / v_total_ant * 100, 1) end,

    'taxaRealizacaoPct', v_taxa_realizacao,
    'taxaRealizacaoDeltaPct', case when v_taxa_realizacao is null or v_taxa_realizacao_ant is null then null else round(v_taxa_realizacao - v_taxa_realizacao_ant, 1) end,

    'taxaFaltaPct', v_taxa_falta,
    'taxaFaltaDeltaPct', case when v_taxa_falta is null or v_taxa_falta_ant is null then null else round(v_taxa_falta - v_taxa_falta_ant, 1) end,

    'pctRecorrentes', v_taxa_recorrentes,
    'pctRecorrentesDeltaPct', case when v_taxa_recorrentes is null or v_taxa_recorrentes_ant is null then null else round(v_taxa_recorrentes - v_taxa_recorrentes_ant, 1) end,

    'valorPrevistoTotal', v_valor_previsto,
    'valorPrevistoDeltaPct', case when v_valor_previsto_ant = 0 then null else round((v_valor_previsto - v_valor_previsto_ant) / v_valor_previsto_ant * 100, 1) end,

    'valorRealizadoTotal', v_valor_realizado,
    'valorRealizadoDeltaPct', case when v_valor_realizado_ant = 0 then null else round((v_valor_realizado - v_valor_realizado_ant) / v_valor_realizado_ant * 100, 1) end,

    'aderenciaPct', v_aderencia,
    'aderenciaDeltaPct', case when v_aderencia is null or v_aderencia_ant is null then null else round(v_aderencia - v_aderencia_ant, 1) end,

    'pctSemPagamento', v_pct_sem_pgto,
    'pctSemPagamentoDeltaPct', case when v_pct_sem_pgto is null or v_pct_sem_pgto_ant is null then null else round(v_pct_sem_pgto - v_pct_sem_pgto_ant, 1) end,

    'receitaPerdidaFaltas', v_perda_faltas,
    'receitaPerdidaFaltasDeltaPct', case when v_perda_faltas_ant = 0 then null else round((v_perda_faltas - v_perda_faltas_ant) / v_perda_faltas_ant * 100, 1) end
  );
end;
$function$;

-- ============================================================
-- 2. bi_agenda_distribuicao — status, tipo e evolução (Fase 1)
-- ============================================================
create or replace function public.bi_agenda_distribuicao(
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

  v_ini date;
  v_fim date;
  v_ini_ant date;
  v_fim_ant date;
  v_dias int;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  v_periodo_dias int;
  v_granularidade text;
  v_status jsonb;
  v_tipo jsonb;
  v_evolucao jsonb;
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

  -- distribuição por status (ordem fixa das colunas conhecidas; qualquer valor novo cai no fim)
  select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'total', total) order by ord, nome), '[]'::jsonb)
    into v_status
  from (
    select
      case "STATUS_AGD"
        when 'AGENDADO' then 'Agendado'
        when 'CONFIRMADA' then 'Confirmada'
        when 'REALIZADA' then 'Realizada'
        when 'FALTA' then 'Falta'
        when 'FEEDBACK' then 'Feedback'
        when 'SEM_VALOR' then 'Sem valor'
        when 'CANCELADO' then 'Cancelado'
        else coalesce("STATUS_AGD", 'Não informado')
      end as nome,
      count(*) as total,
      case "STATUS_AGD"
        when 'AGENDADO' then 1
        when 'CONFIRMADA' then 2
        when 'REALIZADA' then 3
        when 'FALTA' then 4
        when 'FEEDBACK' then 5
        when 'SEM_VALOR' then 6
        when 'CANCELADO' then 7
        else 8
      end as ord
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
    group by "STATUS_AGD"
  ) t;

  -- distribuição por tipo
  select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'total', total) order by ord), '[]'::jsonb)
    into v_tipo
  from (
    select
      case "TIPO_AGD" when 'PRESENCIAL' then 'Presencial' when 'ONLINE' then 'Online' else coalesce("TIPO_AGD", 'Não informado') end as nome,
      count(*) as total,
      case "TIPO_AGD" when 'PRESENCIAL' then 1 when 'ONLINE' then 2 else 3 end as ord
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
    group by "TIPO_AGD"
  ) t;

  -- evolução: diária se período <= 62 dias, mensal caso contrário
  v_periodo_dias := v_fim - v_ini;
  v_granularidade := case when v_periodo_dias <= 62 then 'dia' else 'mes' end;

  if v_granularidade = 'dia' then
    with dias as (
      select generate_series(v_ini, v_fim - 1, interval '1 day')::date as bucket
    ),
    agd as (
      select
        (("DT_AGD" at time zone v_tz)::date) as bucket,
        count(*) as total,
        count(*) filter (where "STATUS_AGD" = 'REALIZADA') as realizados,
        count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
      from "AGENDAMENTO"
      where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
      group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'bucket', to_char(d.bucket, 'YYYY-MM-DD'),
             'total', coalesce(a.total, 0),
             'realizados', coalesce(a.realizados, 0),
             'faltas', coalesce(a.faltas, 0)
           ) order by d.bucket), '[]'::jsonb)
      into v_evolucao
    from dias d
    left join agd a on a.bucket = d.bucket;
  else
    with meses as (
      select generate_series(date_trunc('month', v_ini), date_trunc('month', v_fim - interval '1 day'), interval '1 month')::date as bucket
    ),
    agd as (
      select
        date_trunc('month', ("DT_AGD" at time zone v_tz))::date as bucket,
        count(*) as total,
        count(*) filter (where "STATUS_AGD" = 'REALIZADA') as realizados,
        count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
      from "AGENDAMENTO"
      where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
      group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'bucket', to_char(m.bucket, 'YYYY-MM'),
             'total', coalesce(a.total, 0),
             'realizados', coalesce(a.realizados, 0),
             'faltas', coalesce(a.faltas, 0)
           ) order by m.bucket), '[]'::jsonb)
      into v_evolucao
    from meses m
    left join agd a on a.bucket = m.bucket;
  end if;

  return jsonb_build_object(
    'granularidade', v_granularidade,
    'porStatus', v_status,
    'porTipo', v_tipo,
    'evolucao', v_evolucao
  );
end;
$function$;

-- ============================================================
-- 3. bi_agenda_ocupacao — ranking profissionais e salas (Fase 2)
-- ============================================================
create or replace function public.bi_agenda_ocupacao(
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

  v_ini date;
  v_fim date;
  v_ini_ant date;
  v_fim_ant date;
  v_dias int;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  v_por_profissional jsonb;
  v_por_sala jsonb;
  v_salas_ativas bigint;
  v_salas_com_uso bigint;
  v_duracao_media_minutos numeric;
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

  -- ranking por profissional (base = todos os profissionais ativos, mesmo sem agendamento no período)
  select coalesce(jsonb_agg(jsonb_build_object(
           'idProf', p."ID_PROF",
           'nome', p."NOME_PROF",
           'totalAgendamentos', coalesce(a.total, 0),
           'horasAgendadas', round(coalesce(a.minutos, 0) / 60.0, 1),
           'faltas', coalesce(a.faltas, 0),
           'taxaFaltaPct', case when coalesce(a.total, 0) = 0 then null else round(coalesce(a.faltas, 0)::numeric / a.total * 100, 1) end
         ) order by coalesce(a.total, 0) desc, p."NOME_PROF"), '[]'::jsonb)
    into v_por_profissional
  from "PROFISSIONAL" p
  left join (
    select
      "PROF_AGD" as id_prof,
      count(*) as total,
      count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas,
      sum(extract(epoch from ("DT_FIM_AGD" - "DT_AGD")) / 60.0) as minutos
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts and "PROF_AGD" is not null
    group by "PROF_AGD"
  ) a on a.id_prof = p."ID_PROF"
  where p."ID_EMP" = p_id_emp and p."ATIVO_PROF" is true;

  -- ranking por sala (base = todas as salas ativas, mesmo sem uso no período)
  select coalesce(jsonb_agg(jsonb_build_object(
           'idSala', s."ID_SALA",
           'nome', s."NOME_SALA",
           'totalAgendamentos', coalesce(a.total, 0),
           'horasOcupadas', round(coalesce(a.minutos, 0) / 60.0, 1)
         ) order by coalesce(a.total, 0) desc, s."NOME_SALA"), '[]'::jsonb)
    into v_por_sala
  from "SALA" s
  left join (
    select
      "SALA_AGD" as id_sala,
      count(*) as total,
      sum(extract(epoch from ("DT_FIM_AGD" - "DT_AGD")) / 60.0) as minutos
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts and "SALA_AGD" is not null
    group by "SALA_AGD"
  ) a on a.id_sala = s."ID_SALA"
  where s."ID_EMP" = p_id_emp and s."ATIVO_SALA" is true;

  select count(*) into v_salas_ativas from "SALA" where "ID_EMP" = p_id_emp and "ATIVO_SALA" is true;

  select count(distinct "SALA_AGD") into v_salas_com_uso
  from "AGENDAMENTO"
  where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts and "SALA_AGD" is not null;

  select round(avg(extract(epoch from ("DT_FIM_AGD" - "DT_AGD")) / 60.0), 1) into v_duracao_media_minutos
  from "AGENDAMENTO"
  where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts;

  return jsonb_build_object(
    'porProfissional', v_por_profissional,
    'porSala', v_por_sala,
    'salasAtivas', v_salas_ativas,
    'salasComUso', v_salas_com_uso,
    'duracaoMediaMinutos', v_duracao_media_minutos
  );
end;
$function$;

-- ============================================================
-- 4. bi_agenda_padroes — heatmap e antecedência (Fase 3)
-- ============================================================
create or replace function public.bi_agenda_padroes(
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

  v_ini date;
  v_fim date;
  v_ini_ant date;
  v_fim_ant date;
  v_dias int;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  v_heatmap jsonb;
  v_por_dia_semana jsonb;
  v_antecedencia_media_horas numeric;
  v_pct_cima_hora numeric;
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

  -- heatmap dia da semana (0=domingo..6=sábado) x hora do dia (0-23)
  select coalesce(jsonb_agg(jsonb_build_object('dow', dow, 'hour', hour, 'total', total)), '[]'::jsonb)
    into v_heatmap
  from (
    select
      date_part('dow', "DT_AGD" at time zone v_tz)::int as dow,
      date_part('hour', "DT_AGD" at time zone v_tz)::int as hour,
      count(*) as total
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
    group by 1, 2
  ) t;

  -- distribuição por dia da semana
  select coalesce(jsonb_agg(jsonb_build_object('dow', dow, 'total', total) order by dow), '[]'::jsonb)
    into v_por_dia_semana
  from (
    select date_part('dow', "DT_AGD" at time zone v_tz)::int as dow, count(*) as total
    from "AGENDAMENTO"
    where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
    group by 1
  ) t;

  select
    round(avg(extract(epoch from ("DT_AGD" - "DTCRI_AGD")) / 3600.0), 1),
    round(
      count(*) filter (where "DT_AGD" - "DTCRI_AGD" < interval '24 hours')::numeric
      / greatest(count(*), 1) * 100, 1)
  into v_antecedencia_media_horas, v_pct_cima_hora
  from "AGENDAMENTO"
  where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts;

  return jsonb_build_object(
    'heatmap', v_heatmap,
    'porDiaSemana', v_por_dia_semana,
    'antecedenciaMediaHoras', v_antecedencia_media_horas,
    'pctCimaHora', v_pct_cima_hora
  );
end;
$function$;
