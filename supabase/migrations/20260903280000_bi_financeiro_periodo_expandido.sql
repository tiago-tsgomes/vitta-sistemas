-- Expande o filtro de período do Financeiro (bi/pages/financeiro.html), a
-- pedido do usuário em 03/09/2026, que enviou um mockup com mais opções
-- (Hoje, Ontem, Últimos 7 dias, Últimos 30 dias, Este mês, Mês passado,
-- Trimestre, Ano (YTD)) e uma opção "Personalizado..." com calendário de
-- intervalo livre (INÍCIO/FIM escolhidos pelo usuário).
--
-- Vocabulário novo de p_period: hoje, ontem, 7dias, 30dias, mes,
-- mes_passado, trimestre, ano, custom. "trimestre" substitui "semestre"
-- (era 6 meses corridos, agora é 3, igual ao mockup enviado — não afeta
-- bi_trend_data/dashboard.html, que tem seu próprio "semestre" independente).
-- "custom" exige p_data_ini/p_data_fim (novos parâmetros, ambos inclusive).
--
-- Cada período continua comparando com o intervalo equivalente IMEDIATAMENTE
-- anterior (mesma quantidade de dias antes do início, exceto mes/mes_passado/
-- ano que seguem a lógica de calendário já existente). Para "custom", o
-- período anterior é o mesmo número de dias imediatamente antes de INÍCIO.
--
-- CREATE OR REPLACE não substitui uma função quando a lista de parâmetros
-- muda — remove as assinaturas antigas antes de recriar.

drop function if exists public.bi_financeiro_resumo(uuid, text, uuid);
drop function if exists public.bi_financeiro_por_profissional(uuid, text);

create or replace function public.bi_financeiro_resumo(
  p_id_emp uuid,
  p_period text default 'mes',
  p_id_prof uuid default null,
  p_data_ini date default null,
  p_data_fim date default null
)
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

  v_recebido numeric; v_qtd_pgto bigint; v_repasse numeric;
  v_recebido_ant numeric; v_qtd_pgto_ant bigint; v_repasse_ant numeric;
  v_liquido numeric; v_liquido_ant numeric;

  v_estornado numeric; v_estornado_ant numeric;

  v_realizadas bigint; v_faltas bigint;
  v_realizadas_ant bigint; v_faltas_ant bigint;

  v_ticket_atend numeric; v_ticket_atend_ant numeric;
  v_ticket_pgto numeric; v_ticket_pgto_ant numeric;

  v_perda_faltas numeric; v_perda_faltas_ant numeric;
begin
  perform bi_check_access(p_id_emp);

  if p_period not in ('hoje', 'ontem', '7dias', '30dias', 'mes', 'mes_passado', 'trimestre', 'ano', 'custom') then
    raise exception 'período inválido: %', p_period;
  end if;

  if p_period = 'hoje' then
    v_ini := v_hoje;
    v_fim := v_hoje + 1;
    v_ini_ant := v_hoje - 1;
    v_fim_ant := v_hoje;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1;
    v_fim := v_hoje;
    v_ini_ant := v_hoje - 2;
    v_fim_ant := v_hoje - 1;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6;
    v_fim := v_hoje + 1;
    v_ini_ant := v_ini - 7;
    v_fim_ant := v_ini;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29;
    v_fim := v_hoje + 1;
    v_ini_ant := v_ini - 30;
    v_fim_ant := v_ini;
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
      raise exception 'período customizado inválido: p_data_ini/p_data_fim';
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

  select coalesce(sum(p."VL_PGTO"), 0), count(*),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0)
    into v_recebido, v_qtd_pgto, v_repasse
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and (p_id_prof is null or a."PROF_AGD" = p_id_prof)
      and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim;

  select coalesce(sum(p."VL_PGTO"), 0), count(*),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0)
    into v_recebido_ant, v_qtd_pgto_ant, v_repasse_ant
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and (p_id_prof is null or a."PROF_AGD" = p_id_prof)
      and p."DT_PGTO" >= v_ini_ant and p."DT_PGTO" < v_fim_ant;

  v_liquido := v_recebido - v_repasse;
  v_liquido_ant := v_recebido_ant - v_repasse_ant;

  select coalesce(sum(p."VL_PGTO"), 0) into v_estornado
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is true
      and (p_id_prof is null or a."PROF_AGD" = p_id_prof)
      and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim;

  select coalesce(sum(p."VL_PGTO"), 0) into v_estornado_ant
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is true
      and (p_id_prof is null or a."PROF_AGD" = p_id_prof)
      and p."DT_PGTO" >= v_ini_ant and p."DT_PGTO" < v_fim_ant;

  select count(*) filter (where "STATUS_AGD" = 'REALIZADA'),
         count(*) filter (where "STATUS_AGD" = 'FALTA')
    into v_realizadas, v_faltas
    from "AGENDAMENTO" where "ID_EMP" = p_id_emp
      and (p_id_prof is null or "PROF_AGD" = p_id_prof)
      and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts;

  select count(*) filter (where "STATUS_AGD" = 'REALIZADA'),
         count(*) filter (where "STATUS_AGD" = 'FALTA')
    into v_realizadas_ant, v_faltas_ant
    from "AGENDAMENTO" where "ID_EMP" = p_id_emp
      and (p_id_prof is null or "PROF_AGD" = p_id_prof)
      and "DT_AGD" >= v_ini_ant_ts and "DT_AGD" < v_fim_ant_ts;

  v_ticket_pgto := case when v_qtd_pgto = 0 then 0 else round(v_recebido / v_qtd_pgto, 2) end;
  v_ticket_pgto_ant := case when v_qtd_pgto_ant = 0 then 0 else round(v_recebido_ant / v_qtd_pgto_ant, 2) end;

  v_ticket_atend := case when v_realizadas = 0 then 0 else round(v_recebido / v_realizadas, 2) end;
  v_ticket_atend_ant := case when v_realizadas_ant = 0 then 0 else round(v_recebido_ant / v_realizadas_ant, 2) end;

  v_perda_faltas := round(v_faltas * v_ticket_atend, 2);
  v_perda_faltas_ant := round(v_faltas_ant * v_ticket_atend_ant, 2);

  return jsonb_build_object(
    'recebidoMes', round(v_recebido, 2),
    'recebidoDeltaPct', case when v_recebido_ant = 0 then null else round((v_recebido - v_recebido_ant) / v_recebido_ant * 100, 1) end,

    'repasseClinicaMes', round(v_repasse, 2),
    'repasseDeltaPct', case when v_repasse_ant = 0 then null else round((v_repasse - v_repasse_ant) / v_repasse_ant * 100, 1) end,

    'liquidoProfMes', round(v_liquido, 2),
    'liquidoDeltaPct', case when v_liquido_ant = 0 then null else round((v_liquido - v_liquido_ant) / v_liquido_ant * 100, 1) end,

    'ticketAtendimento', v_ticket_atend,
    'ticketAtendimentoDeltaPct', case when v_ticket_atend_ant = 0 then null else round((v_ticket_atend - v_ticket_atend_ant) / v_ticket_atend_ant * 100, 1) end,

    'ticketPagamento', v_ticket_pgto,
    'ticketPagamentoDeltaPct', case when v_ticket_pgto_ant = 0 then null else round((v_ticket_pgto - v_ticket_pgto_ant) / v_ticket_pgto_ant * 100, 1) end,

    'qtdPagamentos', v_qtd_pgto,
    'qtdPagamentosDeltaPct', case when v_qtd_pgto_ant = 0 then null else round((v_qtd_pgto - v_qtd_pgto_ant)::numeric / v_qtd_pgto_ant * 100, 1) end,

    'estornadoMes', round(v_estornado, 2),
    'estornadoDeltaPct', case when v_estornado_ant = 0 then null else round((v_estornado - v_estornado_ant) / v_estornado_ant * 100, 1) end,
    'estornadoPctBruto', case when (v_recebido + v_estornado) = 0 then null else round(v_estornado / (v_recebido + v_estornado) * 100, 1) end,

    'faltasMes', v_faltas,
    'faltasDeltaPct', case when v_faltas_ant = 0 then null else round((v_faltas - v_faltas_ant)::numeric / v_faltas_ant * 100, 1) end,
    'perdaFaltasEstimada', v_perda_faltas
  );
end;
$$;

create or replace function public.bi_financeiro_por_profissional(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
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
  v_ini_ly date;
  v_fim_ly date;
  v_dias int;

  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  result jsonb;
begin
  perform bi_check_access(p_id_emp);

  if p_period not in ('hoje', 'ontem', '7dias', '30dias', 'mes', 'mes_passado', 'trimestre', 'ano', 'custom') then
    raise exception 'período inválido: %', p_period;
  end if;

  if p_period = 'hoje' then
    v_ini := v_hoje;
    v_fim := v_hoje + 1;
    v_ini_ant := v_hoje - 1;
    v_fim_ant := v_hoje;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1;
    v_fim := v_hoje;
    v_ini_ant := v_hoje - 2;
    v_fim_ant := v_hoje - 1;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6;
    v_fim := v_hoje + 1;
    v_ini_ant := v_ini - 7;
    v_fim_ant := v_ini;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29;
    v_fim := v_hoje + 1;
    v_ini_ant := v_ini - 30;
    v_fim_ant := v_ini;
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
      raise exception 'período customizado inválido: p_data_ini/p_data_fim';
    end if;
    v_ini := p_data_ini;
    v_fim := p_data_fim + 1;
    v_dias := v_fim - v_ini;
    v_ini_ant := v_ini - v_dias;
    v_fim_ant := v_ini;
  end if;

  v_ini_ly := (v_ini - interval '1 year')::date;
  v_fim_ly := (v_fim - interval '1 year')::date;

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
  ano_anterior as (
    select a."PROF_AGD" as id_prof,
           coalesce(sum(p."VL_PGTO"), 0) as recebido
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and a."PROF_AGD" is not null
        and p."DT_PGTO" >= v_ini_ly and p."DT_PGTO" < v_fim_ly
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
      'recebidoDeltaPctLM', case when coalesce(an.recebido, 0) = 0 then null
                             else round((coalesce(at.recebido, 0) - an.recebido) / an.recebido * 100, 1) end,
      'recebidoDeltaPctLY', case when coalesce(ly.recebido, 0) = 0 then null
                             else round((coalesce(at.recebido, 0) - ly.recebido) / ly.recebido * 100, 1) end,
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
  left join ano_anterior ly on ly.id_prof = pr."ID_PROF"
  left join agd_atual ag on ag.id_prof = pr."ID_PROF"
  where pr."ID_EMP" = p_id_emp and pr."ATIVO_PROF" is true;

  return jsonb_build_object('profissionais', result);
end;
$$;
