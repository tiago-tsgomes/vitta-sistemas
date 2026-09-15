-- Corrige a comparação de % dos KPIs mensais do Vitta BI: antes comparava
-- "mês corrente até hoje" (parcial) contra "mês anterior completo", o que
-- gerava quedas artificiais gigantes nos primeiros dias de cada mês
-- (ex.: dia 3 do mês comparado a 30 dias do mês anterior).
-- Agora compara sempre o mesmo número de dias corridos em ambos os meses
-- (dia 1 até hoje vs. dia 1 até o mesmo dia do mês anterior).
--
-- Também corrige Recebido/Repasse/Ticket para replicar fielmente
-- pages/financeiro.html: usa AGENDAMENTO!inner (exclui PAGAMENTO órfão,
-- sem agendamento vinculado — caso real encontrado nesta empresa) e calcula
-- o repasse pelo profissional do AGENDAMENTO (PROF_AGD), não pelo ID_PROF
-- gravado no próprio PAGAMENTO.

create or replace function public.bi_dashboard_kpis(p_id_emp uuid)
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

  v_pac_ativos bigint;
  v_novos bigint; v_novos_ant bigint;
  v_agd bigint; v_agd_ant bigint;
  v_realizadas bigint; v_faltas bigint;
  v_realizadas_ant bigint; v_faltas_ant bigint;
  v_comparecimento numeric; v_comparecimento_ant numeric;
  v_recebido numeric; v_qtd_pgto bigint; v_repasse numeric;
  v_recebido_ant numeric; v_qtd_pgto_ant bigint; v_repasse_ant numeric;
  v_ticket numeric; v_ticket_ant numeric;
begin
  perform bi_check_access(p_id_emp);

  select count(*) into v_pac_ativos
    from "PACIENTE" where "EMP_PAC" = p_id_emp and "ATIVO_PAC" = true;

  select count(*) into v_novos
    from "PACIENTE" where "EMP_PAC" = p_id_emp
      and "DTCRI_PAC" >= v_mes_ini_ts and "DTCRI_PAC" < v_mes_fim_ts;
  select count(*) into v_novos_ant
    from "PACIENTE" where "EMP_PAC" = p_id_emp
      and "DTCRI_PAC" >= v_mes_ant_ini_ts and "DTCRI_PAC" < v_mes_ant_fim_ts;

  select count(*) into v_agd
    from "AGENDAMENTO" where "ID_EMP" = p_id_emp
      and "DT_AGD" >= v_mes_ini_ts and "DT_AGD" < v_mes_fim_ts;
  select count(*) into v_agd_ant
    from "AGENDAMENTO" where "ID_EMP" = p_id_emp
      and "DT_AGD" >= v_mes_ant_ini_ts and "DT_AGD" < v_mes_ant_fim_ts;

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

  v_comparecimento := case when (v_realizadas + v_faltas) = 0 then null
    else round(v_realizadas::numeric / (v_realizadas + v_faltas) * 100, 1) end;
  v_comparecimento_ant := case when (v_realizadas_ant + v_faltas_ant) = 0 then null
    else round(v_realizadas_ant::numeric / (v_realizadas_ant + v_faltas_ant) * 100, 1) end;

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

  v_ticket := case when v_qtd_pgto = 0 then 0 else round(v_recebido / v_qtd_pgto, 2) end;
  v_ticket_ant := case when v_qtd_pgto_ant = 0 then 0 else round(v_recebido_ant / v_qtd_pgto_ant, 2) end;

  return jsonb_build_object(
    'pacientesAtivos', v_pac_ativos,
    'novosPacientesMes', v_novos,
    'novosPacientesDeltaPct', case when v_novos_ant = 0 then null else round((v_novos - v_novos_ant)::numeric / v_novos_ant * 100, 1) end,
    'agendamentosMes', v_agd,
    'agendamentosDeltaPct', case when v_agd_ant = 0 then null else round((v_agd - v_agd_ant)::numeric / v_agd_ant * 100, 1) end,
    'comparecimentoPct', v_comparecimento,
    'comparecimentoDeltaPp', case when v_comparecimento is null or v_comparecimento_ant is null then null else round(v_comparecimento - v_comparecimento_ant, 1) end,
    'recebidoMes', round(v_recebido, 2),
    'recebidoDeltaPct', case when v_recebido_ant = 0 then null else round((v_recebido - v_recebido_ant) / v_recebido_ant * 100, 1) end,
    'repasseClinicaMes', round(v_repasse, 2),
    'repasseDeltaPct', case when v_repasse_ant = 0 then null else round((v_repasse - v_repasse_ant) / v_repasse_ant * 100, 1) end,
    'ticketMedio', v_ticket,
    'ticketDeltaPct', case when v_ticket_ant = 0 then null else round((v_ticket - v_ticket_ant) / v_ticket_ant * 100, 1) end
  );
end;
$$;
