-- Ativa os filtros do topo de bi/pages/financeiro.html (período e
-- profissional), que até aqui eram só divs decorativas sem lógica.
--
-- 1) bi_financeiro_resumo ganha p_period e p_id_prof (ambos opcionais,
--    default 'mes' / null, compatível com a chamada já publicada).
--    p_period segue o mesmo vocabulário do dashboard (mes/mes_passado/
--    semestre/ano); cada período compara sempre com o intervalo
--    equivalente imediatamente anterior.
-- 2) bi_financeiro_filtros(p_id_emp) lista os profissionais ativos da
--    empresa para popular o select de "Profissional".
--
-- O filtro "forma de pagamento" NÃO foi ativado: checamos os dados reais
-- e PAGAMENTO.FORMA_PGTO está 100% nulo e PAGAMENTO.ID_TIPPAG está nulo
-- em ~91% dos registros nesta base — um filtro por forma de pagamento
-- hoje esconderia quase todo o histórico em vez de filtrar de verdade.
-- Fica pendente até a forma de pagamento passar a ser registrada de
-- forma consistente no cadastro de pagamentos.

create or replace function public.bi_financeiro_filtros(p_id_emp uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform bi_check_access(p_id_emp);

  select jsonb_build_object(
    'profissionais', coalesce(jsonb_agg(
      jsonb_build_object('id', pr."ID_PROF", 'nome', pr."NOME_PROF")
      order by pr."NOME_PROF"
    ), '[]'::jsonb)
  ) into result
  from "PROFISSIONAL" pr
  where pr."ID_EMP" = p_id_emp and pr."ATIVO_PROF" is true;

  return result;
end;
$$;

-- CREATE OR REPLACE não substitui uma função quando a lista de parâmetros
-- muda (mesmo só adicionando parâmetros com default): isso criaria uma
-- segunda função bi_financeiro_resumo sobrecarregada e o PostgREST passaria
-- a ter duas candidatas para resolver. Por isso removemos a assinatura
-- antiga (1 parâmetro) antes de criar a nova (3 parâmetros).
drop function if exists public.bi_financeiro_resumo(uuid);

create or replace function public.bi_financeiro_resumo(p_id_emp uuid, p_period text default 'mes', p_id_prof uuid default null)
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
