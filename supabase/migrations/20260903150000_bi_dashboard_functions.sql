-- Vitta BI — dados reais do dashboard, isolados por empresa.
-- Substitui o mock DASHBOARD_DATA de bi/pages/dashboard.html.
-- Regra inegociável: nenhuma função aqui pode misturar dados de empresas
-- diferentes. p_id_emp é sempre validado contra o vínculo real do usuário
-- autenticado (USUARIO.AUTH_ID = auth.uid()) e contra EMPRESA.BI_ACESSO_EMP.

create or replace function public.bi_check_access(p_id_emp uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
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

  if not exists (
    select 1 from "EMPRESA" e
    where e."ID_EMP" = p_id_emp
      and e."BI_ACESSO_EMP" = true
  ) then
    raise exception 'Vitta BI não habilitado para esta empresa';
  end if;
end;
$$;

revoke all on function public.bi_check_access(uuid) from public;
grant execute on function public.bi_check_access(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- bi_dashboard_kpis: 7 indicadores do mês corrente + variação vs mês anterior
-- ---------------------------------------------------------------------
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
  v_mes_fim date := (date_trunc('month', v_hoje) + interval '1 month')::date;
  v_mes_ant_ini date := (date_trunc('month', v_hoje) - interval '1 month')::date;
  v_mes_ant_fim date := v_mes_ini;

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
    left join "PROFISSIONAL" pr on pr."ID_PROF" = p."ID_PROF"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and p."DT_PGTO" >= v_mes_ini and p."DT_PGTO" < v_mes_fim;

  select coalesce(sum(p."VL_PGTO"), 0), count(*),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0)
    into v_recebido_ant, v_qtd_pgto_ant, v_repasse_ant
    from "PAGAMENTO" p
    left join "PROFISSIONAL" pr on pr."ID_PROF" = p."ID_PROF"
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

revoke all on function public.bi_dashboard_kpis(uuid) from public;
grant execute on function public.bi_dashboard_kpis(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- bi_trend_data: séries por período (mes = 4 semanas, semestre = 6 meses,
-- ano = 12 meses), mesmo shape usado hoje pelo DASHBOARD_DATA mock.
-- ---------------------------------------------------------------------
create or replace function public.bi_trend_data(p_id_emp uuid, p_period text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_mes_atual date := date_trunc('month', v_hoje)::date;
  v_labels_pt constant text[] := array['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
  v_n int;
  result jsonb;
begin
  perform bi_check_access(p_id_emp);

  if p_period not in ('mes','semestre','ano') then
    raise exception 'período inválido: %', p_period;
  end if;

  create temporary table _bi_buckets (
    idx int,
    label text,
    ini date,
    fim date
  ) on commit drop;

  if p_period = 'mes' then
    for v_n in 0..3 loop
      insert into _bi_buckets values (
        v_n,
        'Sem ' || (v_n + 1),
        v_mes_atual + (v_n * 7),
        case when v_n = 3 then (v_mes_atual + interval '1 month')::date
             else v_mes_atual + ((v_n + 1) * 7) end
      );
    end loop;
  elsif p_period = 'semestre' then
    for v_n in 0..5 loop
      insert into _bi_buckets values (
        v_n,
        v_labels_pt[extract(month from (v_mes_atual - ((5 - v_n) * interval '1 month')))::int],
        (v_mes_atual - ((5 - v_n) * interval '1 month'))::date,
        (v_mes_atual - ((5 - v_n) * interval '1 month') + interval '1 month')::date
      );
    end loop;
  else
    for v_n in 0..11 loop
      insert into _bi_buckets values (
        v_n,
        v_labels_pt[extract(month from (v_mes_atual - ((11 - v_n) * interval '1 month')))::int],
        (v_mes_atual - ((11 - v_n) * interval '1 month'))::date,
        (v_mes_atual - ((11 - v_n) * interval '1 month') + interval '1 month')::date
      );
    end loop;
  end if;

  select jsonb_build_object(
    'labels', array_agg(b.label order by b.idx),
    'pacientesAtivos', array_agg(
      (select count(*) from "PACIENTE" pc
        where pc."EMP_PAC" = p_id_emp and pc."ATIVO_PAC" = true
          and pc."DTCRI_PAC" < (b.fim::timestamp at time zone v_tz))
      order by b.idx),
    'pacientesNovos', array_agg(
      (select count(*) from "PACIENTE" pc
        where pc."EMP_PAC" = p_id_emp
          and pc."DTCRI_PAC" >= (b.ini::timestamp at time zone v_tz)
          and pc."DTCRI_PAC" < (b.fim::timestamp at time zone v_tz))
      order by b.idx),
    'agendRealizados', array_agg(
      (select count(*) from "AGENDAMENTO" a
        where a."ID_EMP" = p_id_emp and a."STATUS_AGD" = 'REALIZADA'
          and a."DT_AGD" >= (b.ini::timestamp at time zone v_tz)
          and a."DT_AGD" < (b.fim::timestamp at time zone v_tz))
      order by b.idx),
    'agendFaltas', array_agg(
      (select count(*) from "AGENDAMENTO" a
        where a."ID_EMP" = p_id_emp and a."STATUS_AGD" = 'FALTA'
          and a."DT_AGD" >= (b.ini::timestamp at time zone v_tz)
          and a."DT_AGD" < (b.fim::timestamp at time zone v_tz))
      order by b.idx),
    'repasseClinica', array_agg(
      round((select coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0)
              from "PAGAMENTO" p left join "PROFISSIONAL" pr on pr."ID_PROF" = p."ID_PROF"
              where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
                and p."DT_PGTO" >= b.ini and p."DT_PGTO" < b.fim), 2)
      order by b.idx),
    'liquidoProf', array_agg(
      round((select coalesce(sum(p."VL_PGTO" * (1 - coalesce(pr."PERC_PROF", 0) / 100.0)), 0)
              from "PAGAMENTO" p left join "PROFISSIONAL" pr on pr."ID_PROF" = p."ID_PROF"
              where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
                and p."DT_PGTO" >= b.ini and p."DT_PGTO" < b.fim), 2)
      order by b.idx)
  ) into result
  from _bi_buckets b;

  return result;
end;
$$;

revoke all on function public.bi_trend_data(uuid, text) from public;
grant execute on function public.bi_trend_data(uuid, text) to authenticated;
