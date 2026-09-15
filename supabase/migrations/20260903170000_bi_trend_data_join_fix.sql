-- Mesma correção de bi_dashboard_kpis aplicada às séries de tendência:
-- repasseClinica/liquidoProf devem excluir PAGAMENTO órfão (sem AGENDAMENTO
-- vinculado) e usar o profissional do AGENDAMENTO (PROF_AGD), replicando
-- fielmente pages/financeiro.html.

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
              from "PAGAMENTO" p
              inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
              left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
              where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
                and p."DT_PGTO" >= b.ini and p."DT_PGTO" < b.fim), 2)
      order by b.idx),
    'liquidoProf', array_agg(
      round((select coalesce(sum(p."VL_PGTO" * (1 - coalesce(pr."PERC_PROF", 0) / 100.0)), 0)
              from "PAGAMENTO" p
              inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
              left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
              where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
                and p."DT_PGTO" >= b.ini and p."DT_PGTO" < b.fim), 2)
      order by b.idx)
  ) into result
  from _bi_buckets b;

  return result;
end;
$$;
