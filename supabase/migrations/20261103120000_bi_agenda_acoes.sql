-- ============================================================
-- Vitta BI — Agenda & Ocupação: novos blocos (1 a 9)
--
--   bi_agenda_proximos(p_id_emp)                      → 1. Próximos dias
--   bi_agenda_acoes(p_id_emp, p_dias_sem_retorno)     → 3. Sem retorno marcado
--                                                       4. Agendamentos esquecidos
--                                                       5. Pacotes/séries terminando
--   bi_agenda_faltas(p_id_emp, período)               → 2. Faltas em detalhe
--                                                       9. Online por profissional
--   bi_agenda_complementos(p_id_emp, período)         → 6. Bloqueios de agenda
--                                                       7. Atendimentos sem prontuário
--                                                       8. A receber
--
-- Todas chamam bi_check_access(p_id_emp) antes de calcular (só o
-- Administrador de empresa com BI liberado). Blocos 1, 3, 4 e 5 olham
-- para "agora" e não dependem do filtro de período; os demais seguem o
-- período do topo (mesma regra de bi_periodo_range).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Próximos dias
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bi_agenda_proximos(p_id_emp uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_agora timestamptz := now();
  v_fim7 timestamptz;
  v_fim30 timestamptz;
  r7 record;
  r30 record;
  v_por_dia jsonb;
  v_nao_confirmados jsonb;
begin
  perform bi_check_access(p_id_emp);

  v_fim7  := (v_hoje + 7)::timestamp at time zone v_tz;
  v_fim30 := (v_hoje + 30)::timestamp at time zone v_tz;

  select count(*) as total,
         count(*) filter (where "STATUS_AGD" = 'CONFIRMADA') as confirmados,
         count(*) filter (where "STATUS_AGD" = 'AGENDADO')   as nao_confirmados,
         coalesce(sum("VALOR_PREVISTO_AGD"), 0)              as valor
    into r7
    from "AGENDAMENTO"
   where "ID_EMP" = p_id_emp and "DT_AGD" >= v_agora and "DT_AGD" < v_fim7
     and coalesce("STATUS_AGD", '') not in ('FALTA', 'CANCELADO');

  select count(*) as total,
         count(*) filter (where "STATUS_AGD" = 'CONFIRMADA') as confirmados,
         count(*) filter (where "STATUS_AGD" = 'AGENDADO')   as nao_confirmados,
         coalesce(sum("VALOR_PREVISTO_AGD"), 0)              as valor
    into r30
    from "AGENDAMENTO"
   where "ID_EMP" = p_id_emp and "DT_AGD" >= v_agora and "DT_AGD" < v_fim30
     and coalesce("STATUS_AGD", '') not in ('FALTA', 'CANCELADO');

  select coalesce(jsonb_agg(jsonb_build_object(
           'data', d::date, 'total', coalesce(t.total, 0),
           'confirmados', coalesce(t.confirmados, 0),
           'naoConfirmados', coalesce(t.nao_confirmados, 0)) order by d), '[]'::jsonb)
    into v_por_dia
    from generate_series(v_hoje, v_hoje + 6, interval '1 day') d
    left join (
      select ("DT_AGD" at time zone v_tz)::date as dia,
             count(*) as total,
             count(*) filter (where "STATUS_AGD" = 'CONFIRMADA') as confirmados,
             count(*) filter (where "STATUS_AGD" = 'AGENDADO')   as nao_confirmados
        from "AGENDAMENTO"
       where "ID_EMP" = p_id_emp and "DT_AGD" >= v_agora and "DT_AGD" < v_fim7
         and coalesce("STATUS_AGD", '') not in ('FALTA', 'CANCELADO')
       group by 1
    ) t on t.dia = d::date;

  select coalesce(jsonb_agg(x order by x->>'dt'), '[]'::jsonb)
    into v_nao_confirmados
    from (
      select jsonb_build_object(
               'dt', a."DT_AGD",
               'paciente', p."NOME_PAC",
               'telefone', p."TEL_PAC",
               'profissional', pr."NOME_PROF",
               'tipo', a."TIPO_AGD") as x
        from "AGENDAMENTO" a
        left join "PACIENTE" p      on p."ID_PAC"   = a."PAC_AGD"
        left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
       where a."ID_EMP" = p_id_emp and a."DT_AGD" >= v_agora and a."DT_AGD" < v_fim7
         and a."STATUS_AGD" = 'AGENDADO'
       order by a."DT_AGD"
       limit 50
    ) s;

  return jsonb_build_object(
    'proximos7',  jsonb_build_object('total', r7.total,  'confirmados', r7.confirmados,  'naoConfirmados', r7.nao_confirmados,  'valorPrevisto', r7.valor),
    'proximos30', jsonb_build_object('total', r30.total, 'confirmados', r30.confirmados, 'naoConfirmados', r30.nao_confirmados, 'valorPrevisto', r30.valor),
    'porDia', v_por_dia,
    'naoConfirmados', v_nao_confirmados
  );
end;
$$;

-- ------------------------------------------------------------
-- 3, 4 e 5. Ações: sem retorno, esquecidos, séries terminando
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bi_agenda_acoes(p_id_emp uuid, p_dias_sem_retorno integer DEFAULT 60)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_agora timestamptz := now();
  v_inicio_hoje timestamptz;
  v_dias int := greatest(coalesce(p_dias_sem_retorno, 60), 1);

  v_sem_retorno_total bigint;
  v_sem_retorno jsonb;
  v_esq_total bigint;
  v_esq_90 bigint;
  v_esq_por_prof jsonb;
  v_esq_lista jsonb;
  v_series_total bigint;
  v_series jsonb;
begin
  perform bi_check_access(p_id_emp);
  v_inicio_hoje := v_hoje::timestamp at time zone v_tz;

  -- 3. Pacientes atendidos nos últimos N dias sem nenhum agendamento futuro
  with ult as (
    select a."PAC_AGD" as pac,
           max(a."DT_AGD") as ultimo
      from "AGENDAMENTO" a
     where a."ID_EMP" = p_id_emp and a."STATUS_AGD" = 'REALIZADA' and a."PAC_AGD" is not null
     group by a."PAC_AGD"
  ), alvo as (
    select u.pac, u.ultimo
      from ult u
      join "PACIENTE" p on p."ID_PAC" = u.pac
     where u.ultimo >= v_agora - make_interval(days => v_dias)
       and coalesce(p."ATIVO_PAC", true)
       and not exists (
         select 1 from "AGENDAMENTO" f
          where f."ID_EMP" = p_id_emp and f."PAC_AGD" = u.pac and f."DT_AGD" >= v_agora
            and coalesce(f."STATUS_AGD", '') not in ('FALTA', 'CANCELADO'))
  )
  select count(*),
         coalesce((
           select jsonb_agg(x order by (x->>'ultimo') desc)
             from (
               select jsonb_build_object(
                        'paciente', p."NOME_PAC",
                        'telefone', p."TEL_PAC",
                        'ultimo', al.ultimo,
                        'diasDesde', (v_hoje - (al.ultimo at time zone v_tz)::date),
                        'profissional', (
                          select pr."NOME_PROF"
                            from "AGENDAMENTO" a2
                            join "PROFISSIONAL" pr on pr."ID_PROF" = a2."PROF_AGD"
                           where a2."ID_EMP" = p_id_emp and a2."PAC_AGD" = al.pac and a2."STATUS_AGD" = 'REALIZADA'
                           order by a2."DT_AGD" desc limit 1)) as x
                 from alvo al
                 join "PACIENTE" p on p."ID_PAC" = al.pac
                order by al.ultimo desc
                limit 100
             ) s), '[]'::jsonb)
    into v_sem_retorno_total, v_sem_retorno
    from alvo;

  -- 4. Agendamentos que já passaram e continuam "Agendado"/"Confirmada"
  select count(*),
         count(*) filter (where "DT_AGD" >= v_inicio_hoje - interval '90 days')
    into v_esq_total, v_esq_90
    from "AGENDAMENTO"
   where "ID_EMP" = p_id_emp and "DT_AGD" < v_inicio_hoje
     and "STATUS_AGD" in ('AGENDADO', 'CONFIRMADA');

  select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'total', total) order by total desc), '[]'::jsonb)
    into v_esq_por_prof
    from (
      select coalesce(pr."NOME_PROF", 'Sem profissional') as nome, count(*) as total
        from "AGENDAMENTO" a
        left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
       where a."ID_EMP" = p_id_emp and a."DT_AGD" < v_inicio_hoje
         and a."DT_AGD" >= v_inicio_hoje - interval '90 days'
         and a."STATUS_AGD" in ('AGENDADO', 'CONFIRMADA')
       group by 1
    ) t;

  select coalesce(jsonb_agg(x order by (x->>'dt') desc), '[]'::jsonb)
    into v_esq_lista
    from (
      select jsonb_build_object(
               'dt', a."DT_AGD",
               'status', a."STATUS_AGD",
               'paciente', p."NOME_PAC",
               'profissional', pr."NOME_PROF") as x
        from "AGENDAMENTO" a
        left join "PACIENTE" p      on p."ID_PAC"   = a."PAC_AGD"
        left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
       where a."ID_EMP" = p_id_emp and a."DT_AGD" < v_inicio_hoje
         and a."DT_AGD" >= v_inicio_hoje - interval '90 days'
         and a."STATUS_AGD" in ('AGENDADO', 'CONFIRMADA')
       order by a."DT_AGD" desc
       limit 50
    ) s;

  -- 5. Séries de "repetir agendamento" cujo último horário cai nas
  --    próximas 2 semanas, sem nenhum agendamento do paciente depois dele
  with s as (
    select "ID_SERIE" as serie,
           max("DT_AGD") as ultimo,
           count(*) filter (where "DT_AGD" >= v_agora and coalesce("STATUS_AGD", '') not in ('FALTA', 'CANCELADO')) as restantes,
           (array_agg("PAC_AGD"  order by "DT_AGD" desc))[1] as pac,
           (array_agg("PROF_AGD" order by "DT_AGD" desc))[1] as prof
      from "AGENDAMENTO"
     where "ID_EMP" = p_id_emp and "ID_SERIE" is not null
     group by "ID_SERIE"
  ), alvo as (
    select s.*
      from s
     where s.ultimo >= v_agora and s.ultimo < v_agora + interval '14 days'
       and not exists (
         select 1 from "AGENDAMENTO" f
          where f."ID_EMP" = p_id_emp and f."PAC_AGD" = s.pac and f."DT_AGD" > s.ultimo
            and coalesce(f."STATUS_AGD", '') not in ('FALTA', 'CANCELADO'))
  )
  select count(*),
         coalesce((
           select jsonb_agg(x order by x->>'ultimo')
             from (
               select jsonb_build_object(
                        'paciente', p."NOME_PAC",
                        'telefone', p."TEL_PAC",
                        'profissional', pr."NOME_PROF",
                        'ultimo', al.ultimo,
                        'restantes', al.restantes) as x
                 from alvo al
                 left join "PACIENTE" p      on p."ID_PAC"   = al.pac
                 left join "PROFISSIONAL" pr on pr."ID_PROF" = al.prof
                order by al.ultimo
                limit 100
             ) q), '[]'::jsonb)
    into v_series_total, v_series
    from alvo;

  return jsonb_build_object(
    'diasSemRetorno', v_dias,
    'semRetornoTotal', v_sem_retorno_total,
    'semRetorno', v_sem_retorno,
    'esquecidosTotal', v_esq_total,
    'esquecidos90', v_esq_90,
    'esquecidosPorProfissional', v_esq_por_prof,
    'esquecidosLista', v_esq_lista,
    'seriesTerminandoTotal', v_series_total,
    'seriesTerminando', v_series
  );
end;
$$;

-- ------------------------------------------------------------
-- 2 e 9. Faltas em detalhe + online por profissional (período)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bi_agenda_faltas(p_id_emp uuid, p_period text DEFAULT 'mes', p_data_ini date DEFAULT NULL, p_data_fim date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  r record;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;

  v_reincidentes_total bigint;
  v_reincidentes jsonb;
  v_heatmap jsonb;
  v_por_antecedencia jsonb;
  v_por_tipo jsonb;
  v_online_prof jsonb;
begin
  perform bi_check_access(p_id_emp);

  select * into r from bi_periodo_range(p_period, p_data_ini, p_data_fim);
  v_ini_ts := r.v_ini::timestamp at time zone v_tz;
  v_fim_ts := r.v_fim::timestamp at time zone v_tz;

  -- Pacientes com 2 ou mais faltas no período
  with pf as (
    select "PAC_AGD" as pac,
           count(*) as total,
           count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
      from "AGENDAMENTO"
     where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts and "PAC_AGD" is not null
     group by "PAC_AGD"
    having count(*) filter (where "STATUS_AGD" = 'FALTA') >= 2
  )
  select count(*),
         coalesce((
           select jsonb_agg(x order by (x->>'faltas')::int desc, (x->>'taxa')::numeric desc)
             from (
               select jsonb_build_object(
                        'paciente', p."NOME_PAC",
                        'telefone', p."TEL_PAC",
                        'faltas', pf.faltas,
                        'total', pf.total,
                        'taxa', round(pf.faltas::numeric / greatest(pf.total, 1) * 100, 1)) as x
                 from pf
                 left join "PACIENTE" p on p."ID_PAC" = pf.pac
                order by pf.faltas desc
                limit 20
             ) s), '[]'::jsonb)
    into v_reincidentes_total, v_reincidentes
    from pf;

  -- Mapa de calor de faltas (dia da semana x hora)
  select coalesce(jsonb_agg(jsonb_build_object('dow', dow, 'hour', hour, 'total', total, 'faltas', faltas)), '[]'::jsonb)
    into v_heatmap
    from (
      select date_part('dow',  "DT_AGD" at time zone v_tz)::int as dow,
             date_part('hour', "DT_AGD" at time zone v_tz)::int as hour,
             count(*) as total,
             count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
        from "AGENDAMENTO"
       where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
       group by 1, 2
    ) t;

  -- Falta x antecedência com que o horário foi marcado
  select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'total', total, 'faltas', faltas,
           'taxa', round(faltas::numeric / greatest(total, 1) * 100, 1)) order by ordem), '[]'::jsonb)
    into v_por_antecedencia
    from (
      select case
               when "DT_AGD" - "DTCRI_AGD" < interval '24 hours' then 'Menos de 24h'
               when "DT_AGD" - "DTCRI_AGD" < interval '7 days'   then '1 a 7 dias'
               else 'Mais de 7 dias'
             end as nome,
             case
               when "DT_AGD" - "DTCRI_AGD" < interval '24 hours' then 1
               when "DT_AGD" - "DTCRI_AGD" < interval '7 days'   then 2
               else 3
             end as ordem,
             count(*) as total,
             count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
        from "AGENDAMENTO"
       where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts and "DTCRI_AGD" is not null
       group by 1, 2
    ) t;

  -- Falta: presencial x online
  select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'total', total, 'faltas', faltas,
           'taxa', round(faltas::numeric / greatest(total, 1) * 100, 1)) order by total desc), '[]'::jsonb)
    into v_por_tipo
    from (
      select case coalesce("TIPO_AGD", '') when 'ONLINE' then 'Online' when 'PRESENCIAL' then 'Presencial' else 'Não informado' end as nome,
             count(*) as total,
             count(*) filter (where "STATUS_AGD" = 'FALTA') as faltas
        from "AGENDAMENTO"
       where "ID_EMP" = p_id_emp and "DT_AGD" >= v_ini_ts and "DT_AGD" < v_fim_ts
       group by 1
    ) t;

  -- 9. Online por profissional (profissionais ativos com agendamento no período)
  select coalesce(jsonb_agg(jsonb_build_object(
           'nome', nome, 'total', total, 'online', online,
           'pctOnline', round(online::numeric / greatest(total, 1) * 100, 1),
           'taxaFaltaOnline', case when online = 0 then null else round(faltas_online::numeric / online * 100, 1) end,
           'taxaFaltaPresencial', case when presencial = 0 then null else round(faltas_presencial::numeric / presencial * 100, 1) end
         ) order by total desc), '[]'::jsonb)
    into v_online_prof
    from (
      select pr."NOME_PROF" as nome,
             count(*) as total,
             count(*) filter (where a."TIPO_AGD" = 'ONLINE') as online,
             count(*) filter (where coalesce(a."TIPO_AGD", '') <> 'ONLINE') as presencial,
             count(*) filter (where a."TIPO_AGD" = 'ONLINE' and a."STATUS_AGD" = 'FALTA') as faltas_online,
             count(*) filter (where coalesce(a."TIPO_AGD", '') <> 'ONLINE' and a."STATUS_AGD" = 'FALTA') as faltas_presencial
        from "AGENDAMENTO" a
        join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
       where a."ID_EMP" = p_id_emp and a."DT_AGD" >= v_ini_ts and a."DT_AGD" < v_fim_ts
         and coalesce(pr."ATIVO_PROF", true)
       group by pr."ID_PROF", pr."NOME_PROF"
    ) t;

  return jsonb_build_object(
    'reincidentesTotal', v_reincidentes_total,
    'reincidentes', v_reincidentes,
    'heatmapFaltas', v_heatmap,
    'porAntecedencia', v_por_antecedencia,
    'porTipo', v_por_tipo,
    'onlinePorProfissional', v_online_prof
  );
end;
$$;

-- ------------------------------------------------------------
-- 6, 7 e 8. Bloqueios, prontuário e a receber (período)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bi_agenda_complementos(p_id_emp uuid, p_period text DEFAULT 'mes', p_data_ini date DEFAULT NULL, p_data_fim date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  r record;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;

  v_bloq_qtd bigint;
  v_bloq_horas numeric;
  v_bloq_prof jsonb;
  v_bloq_motivo jsonb;

  v_pront_realizados bigint;
  v_pront_sem_registro bigint;
  v_pront_rascunho bigint;
  v_pront_tempo_medio numeric;
  v_pront_prof jsonb;

  v_rec_qtd bigint;
  v_rec_valor numeric;
  v_rec_prof jsonb;
  v_rec_lista jsonb;
begin
  perform bi_check_access(p_id_emp);

  select * into r from bi_periodo_range(p_period, p_data_ini, p_data_fim);
  v_ini_ts := r.v_ini::timestamp at time zone v_tz;
  v_fim_ts := r.v_fim::timestamp at time zone v_tz;

  -- 6. Bloqueios de agenda que se sobrepõem ao período (horas dentro do período)
  with b as (
    select bp."PROF_BLOQ" as prof,
           coalesce(nullif(trim(bp."MOTIVO_BLOQ"), ''), 'Sem motivo informado') as motivo,
           extract(epoch from (least(bp."DT_FIM", v_fim_ts) - greatest(bp."DT_INICIO", v_ini_ts))) / 3600.0 as horas
      from "BLOQUEIO_PROF" bp
     where bp."ID_EMP" = p_id_emp
       and bp."DT_INICIO" < v_fim_ts and bp."DT_FIM" > v_ini_ts
  )
  select count(*), coalesce(round(sum(horas)::numeric, 1), 0),
         coalesce((
           select jsonb_agg(jsonb_build_object('nome', nome, 'qtd', qtd, 'horas', horas) order by horas desc)
             from (
               select coalesce(pr."NOME_PROF", 'Sem profissional') as nome, count(*) as qtd, round(sum(b2.horas)::numeric, 1) as horas
                 from b b2 left join "PROFISSIONAL" pr on pr."ID_PROF" = b2.prof
                group by 1
             ) t), '[]'::jsonb),
         coalesce((
           select jsonb_agg(jsonb_build_object('nome', motivo, 'qtd', qtd, 'horas', horas) order by horas desc)
             from (
               select motivo, count(*) as qtd, round(sum(horas)::numeric, 1) as horas
                 from b group by motivo order by sum(horas) desc limit 8
             ) t), '[]'::jsonb)
    into v_bloq_qtd, v_bloq_horas, v_bloq_prof, v_bloq_motivo
    from b;

  -- 7. Atendimentos "Realizada" sem registro de consulta (prontuário)
  with re as (
    select a."ID_AGD", a."DT_AGD", a."PROF_AGD",
           c."ID_CONS", c."RASCUNHO", c."DTCRI_CONS"
      from "AGENDAMENTO" a
      left join lateral (
        select c1."ID_CONS", c1."RASCUNHO", c1."DTCRI_CONS"
          from "CONSULTA" c1 where c1."ID_AGD" = a."ID_AGD"
         order by c1."DTCRI_CONS" limit 1
      ) c on true
     where a."ID_EMP" = p_id_emp and a."STATUS_AGD" = 'REALIZADA'
       and a."DT_AGD" >= v_ini_ts and a."DT_AGD" < v_fim_ts
  )
  select count(*),
         count(*) filter (where "ID_CONS" is null),
         count(*) filter (where "RASCUNHO" is true),
         round(avg(extract(epoch from ("DTCRI_CONS" - "DT_AGD")) / 3600.0)
               filter (where "ID_CONS" is not null and "DTCRI_CONS" >= "DT_AGD"), 1),
         coalesce((
           select jsonb_agg(jsonb_build_object('nome', nome, 'realizados', realizados, 'semRegistro', sem_registro,
                    'pct', round(sem_registro::numeric / greatest(realizados, 1) * 100, 1)) order by sem_registro desc)
             from (
               select coalesce(pr."NOME_PROF", 'Sem profissional') as nome,
                      count(*) as realizados,
                      count(*) filter (where re2."ID_CONS" is null) as sem_registro
                 from re re2 left join "PROFISSIONAL" pr on pr."ID_PROF" = re2."PROF_AGD"
                group by 1
             ) t), '[]'::jsonb)
    into v_pront_realizados, v_pront_sem_registro, v_pront_rascunho, v_pront_tempo_medio, v_pront_prof
    from re;

  -- 8. A receber: "Realizada" marcados para cobrança e sem pagamento lançado
  with ar as (
    select a."ID_AGD", a."DT_AGD", a."PROF_AGD", a."PAC_AGD",
           coalesce(a."VALOR_AGD", a."VALOR_PREVISTO_AGD", 0) as valor
      from "AGENDAMENTO" a
     where a."ID_EMP" = p_id_emp and a."STATUS_AGD" = 'REALIZADA' and a."PGTO_AGD" is true
       and a."DT_AGD" >= v_ini_ts and a."DT_AGD" < v_fim_ts
       and not exists (
         select 1 from "PAGAMENTO" pg
          where pg."ID_AGD" = a."ID_AGD" and coalesce(pg."ESTORNADO_PGTO", false) = false)
  )
  select count(*), coalesce(sum(valor), 0),
         coalesce((
           select jsonb_agg(jsonb_build_object('nome', nome, 'qtd', qtd, 'valor', valor) order by valor desc)
             from (
               select coalesce(pr."NOME_PROF", 'Sem profissional') as nome, count(*) as qtd, sum(ar2.valor) as valor
                 from ar ar2 left join "PROFISSIONAL" pr on pr."ID_PROF" = ar2."PROF_AGD"
                group by 1
             ) t), '[]'::jsonb),
         coalesce((
           select jsonb_agg(x order by (x->>'dt') desc)
             from (
               select jsonb_build_object('dt', ar3."DT_AGD", 'paciente', p."NOME_PAC",
                        'profissional', pr."NOME_PROF", 'valor', ar3.valor) as x
                 from ar ar3
                 left join "PACIENTE" p      on p."ID_PAC"   = ar3."PAC_AGD"
                 left join "PROFISSIONAL" pr on pr."ID_PROF" = ar3."PROF_AGD"
                order by ar3."DT_AGD" desc
                limit 50
             ) s), '[]'::jsonb)
    into v_rec_qtd, v_rec_valor, v_rec_prof, v_rec_lista
    from ar;

  return jsonb_build_object(
    'bloqueiosQtd', v_bloq_qtd,
    'bloqueiosHoras', v_bloq_horas,
    'bloqueiosPorProfissional', v_bloq_prof,
    'bloqueiosPorMotivo', v_bloq_motivo,
    'realizados', v_pront_realizados,
    'semProntuario', v_pront_sem_registro,
    'prontuarioRascunho', v_pront_rascunho,
    'tempoMedioRegistroHoras', v_pront_tempo_medio,
    'prontuarioPorProfissional', v_pront_prof,
    'aReceberQtd', v_rec_qtd,
    'aReceberValor', v_rec_valor,
    'aReceberPorProfissional', v_rec_prof,
    'aReceberLista', v_rec_lista
  );
end;
$$;

-- ------------------------------------------------------------
-- Permissões: só usuários logados (o acesso ao BI é conferido dentro)
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.bi_agenda_proximos(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.bi_agenda_acoes(uuid, integer) FROM public, anon;
REVOKE ALL ON FUNCTION public.bi_agenda_faltas(uuid, text, date, date) FROM public, anon;
REVOKE ALL ON FUNCTION public.bi_agenda_complementos(uuid, text, date, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bi_agenda_proximos(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bi_agenda_acoes(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bi_agenda_faltas(uuid, text, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bi_agenda_complementos(uuid, text, date, date) TO authenticated, service_role;
