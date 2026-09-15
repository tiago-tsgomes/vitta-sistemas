-- RPC do resumo financeiro (bi/pages/financeiro.html), seguindo o mesmo padrão
-- de bi_dashboard_kpis: comparação MTD (dia 1 até hoje) vs mesmo intervalo do
-- mês anterior, join AGENDAMENTO!inner (exclui PAGAMENTO órfão) e repasse
-- calculado pelo profissional do AGENDAMENTO (PROF_AGD).
--
-- Nota: os campos VALOR_AGD/VALOR_PREVISTO_AGD do AGENDAMENTO são nulos em
-- ~99% dos registros (inclusive nas REALIZADA) nesta base — não servem como
-- fonte de "taxa de realização de valor" nem "valor perdido em faltas".
-- Por isso "perdaFaltasEstimada" é uma estimativa (nº de faltas × ticket
-- médio por atendimento do próprio período), não um valor real registrado.

create or replace function public.bi_financeiro_resumo(p_id_emp uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;

  v_mes_ini date := date_trunc('month', v_hoje)::date;
  v_dias_decorridos int := (v_hoje - date_trunc('month', v_hoje)::date) + 1;
  v_mes_fim date := v_hoje + 1;
  v_mes_ant_ini date := (date_trunc('month', v_hoje) - interval '1 month')::date;
  v_mes_ant_fim date := v_mes_ant_ini + v_dias_decorridos;

  v_mes_ini_ts timestamptz := v_mes_ini::timestamp at time zone v_tz;
  v_mes_fim_ts timestamptz := v_mes_fim::timestamp at time zone v_tz;
  v_mes_ant_ini_ts timestamptz := v_mes_ant_ini::timestamp at time zone v_tz;
  v_mes_ant_fim_ts timestamptz := v_mes_ant_fim::timestamp at time zone v_tz;

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

  select coalesce(sum(p."VL_PGTO"), 0), count(*),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0)
    into v_recebido, v_qtd_pgto, v_repasse
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and p."DT_PGTO" >= v_mes_ini and p."DT_PGTO" < v_mes_fim;

  select coalesce(sum(p."VL_PGTO"), 0), count(*),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0)
    into v_recebido_ant, v_qtd_pgto_ant, v_repasse_ant
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and p."DT_PGTO" >= v_mes_ant_ini and p."DT_PGTO" < v_mes_ant_fim;

  v_liquido := v_recebido - v_repasse;
  v_liquido_ant := v_recebido_ant - v_repasse_ant;

  select coalesce(sum(p."VL_PGTO"), 0) into v_estornado
    from "PAGAMENTO" p
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is true
      and p."DT_PGTO" >= v_mes_ini and p."DT_PGTO" < v_mes_fim;

  select coalesce(sum(p."VL_PGTO"), 0) into v_estornado_ant
    from "PAGAMENTO" p
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is true
      and p."DT_PGTO" >= v_mes_ant_ini and p."DT_PGTO" < v_mes_ant_fim;

  select count(*) filter (where "STATUS_AGD" = 'REALIZADA'),
         count(*) filter (where "STATUS_AGD" = 'FALTA')
    into v_realizadas, v_faltas
    from "AGENDAMENTO" where "ID_EMP" = p_id_emp
      and "DT_AGD" >= v_mes_ini_ts and "DT_AGD" < v_mes_fim_ts;

  select count(*) filter (where "STATUS_AGD" = 'REALIZADA'),
         count(*) filter (where "STATUS_AGD" = 'FALTA')
    into v_realizadas_ant, v_faltas_ant
    from "AGENDAMENTO" where "ID_EMP" = p_id_emp
      and "DT_AGD" >= v_mes_ant_ini_ts and "DT_AGD" < v_mes_ant_fim_ts;

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
