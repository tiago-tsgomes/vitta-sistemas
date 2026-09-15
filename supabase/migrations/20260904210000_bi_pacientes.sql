-- RPCs do Vitta BI para a tela de Pacientes (bi/pages/pacientes.html), Fase 1
-- do plano em bi/PLANO_BI_PACIENTES.md. Mesma regra inegociável das demais
-- RPCs do BI: nunca consulta direta às tabelas transacionais nem filtro
-- client-side de empresa — todo cálculo passa por bi_check_access(p_id_emp)
-- antes de ler qualquer linha (ver bi_leads_resumo/_por_dimensao em
-- supabase/migrations/20260904190000_bi_leads.sql, mesmo padrão reaproveitado
-- aqui). PACIENTE usa "EMP_PAC" (não "ID_EMP") como FK de empresa.

-- KPIs (cards do topo): pacientes ativos (total atual), novos pacientes no
-- período, consultas realizadas no período e ticket médio no período — os
-- três últimos com comparação ao período equivalente imediatamente anterior,
-- igual a bi_leads_resumo/bi_financeiro_resumo.
create or replace function public.bi_pacientes_resumo(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
returns jsonb
language plpgsql
stable security definer
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

  v_ativos bigint;
  v_novos bigint; v_novos_ant bigint;
  v_consultas bigint; v_consultas_ant bigint;
  v_ticket_medio numeric; v_ticket_medio_ant numeric;
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

  -- pacientes ativos: total atual (não segue o filtro de período)
  select count(*)
    into v_ativos
    from "PACIENTE"
    where "EMP_PAC" = p_id_emp and "ATIVO_PAC" = true;

  select count(*)
    into v_novos
    from "PACIENTE"
    where "EMP_PAC" = p_id_emp and "DTCRI_PAC" >= v_ini_ts and "DTCRI_PAC" < v_fim_ts;

  select count(*)
    into v_novos_ant
    from "PACIENTE"
    where "EMP_PAC" = p_id_emp and "DTCRI_PAC" >= v_ini_ant_ts and "DTCRI_PAC" < v_fim_ant_ts;

  select count(*)
    into v_consultas
    from "CONSULTA"
    where "ID_EMP" = p_id_emp and "DT_CONS" >= v_ini_ts and "DT_CONS" < v_fim_ts;

  select count(*)
    into v_consultas_ant
    from "CONSULTA"
    where "ID_EMP" = p_id_emp and "DT_CONS" >= v_ini_ant_ts and "DT_CONS" < v_fim_ant_ts;

  select round(avg("VL_PGTO"), 2)
    into v_ticket_medio
    from "PAGAMENTO"
    where "ID_EMP" = p_id_emp and coalesce("ESTORNADO_PGTO", false) = false
      and "DT_PGTO" >= v_ini and "DT_PGTO" < v_fim;

  select round(avg("VL_PGTO"), 2)
    into v_ticket_medio_ant
    from "PAGAMENTO"
    where "ID_EMP" = p_id_emp and coalesce("ESTORNADO_PGTO", false) = false
      and "DT_PGTO" >= v_ini_ant and "DT_PGTO" < v_fim_ant;

  return jsonb_build_object(
    'pacientesAtivos', v_ativos,

    'novosPacientes', v_novos,
    'novosPacientesDeltaPct', case when v_novos_ant = 0 then null else round((v_novos - v_novos_ant)::numeric / v_novos_ant * 100, 1) end,

    'consultasRealizadas', v_consultas,
    'consultasRealizadasDeltaPct', case when v_consultas_ant = 0 then null else round((v_consultas - v_consultas_ant)::numeric / v_consultas_ant * 100, 1) end,

    'ticketMedio', v_ticket_medio,
    'ticketMedioDeltaPct', case when v_ticket_medio_ant is null or v_ticket_medio_ant = 0 then null else round((v_ticket_medio - v_ticket_medio_ant) / v_ticket_medio_ant * 100, 1) end
  );
end;
$function$;

-- Gráficos por dimensão: evolução mensal (ano corrente, ativos x novos,
-- mesma definição de bi_trend_data), por profissional (consultas no
-- período), e demografia da base ativa atual (sexo, faixa etária, grupo).
create or replace function public.bi_pacientes_por_dimensao(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
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

  v_ini date;
  v_fim date;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;

  v_evolucao jsonb;
  v_profissional jsonb;
  v_sexo jsonb;
  v_faixa_etaria jsonb;
  v_grupo jsonb;
begin
  perform bi_check_access(p_id_emp);

  if p_period not in ('hoje', 'ontem', '7dias', '30dias', 'mes', 'mes_passado', 'trimestre', 'ano', 'custom') then
    raise exception 'período inválido: %', p_period;
  end if;

  if p_period = 'hoje' then
    v_ini := v_hoje; v_fim := v_hoje + 1;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1; v_fim := v_hoje;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6; v_fim := v_hoje + 1;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29; v_fim := v_hoje + 1;
  elsif p_period = 'mes' then
    v_ini := date_trunc('month', v_hoje)::date; v_fim := v_hoje + 1;
  elsif p_period = 'mes_passado' then
    v_ini := (date_trunc('month', v_hoje) - interval '1 month')::date;
    v_fim := date_trunc('month', v_hoje)::date;
  elsif p_period = 'trimestre' then
    v_ini := (date_trunc('month', v_hoje) - interval '2 month')::date; v_fim := v_hoje + 1;
  elsif p_period = 'ano' then
    v_ini := date_trunc('year', v_hoje)::date; v_fim := v_hoje + 1;
  else
    if p_data_ini is null or p_data_fim is null or p_data_fim < p_data_ini then
      raise exception 'período customizado inválido: p_data_ini/p_data_fim';
    end if;
    v_ini := p_data_ini; v_fim := p_data_fim + 1;
  end if;

  v_ini_ts := v_ini::timestamp at time zone v_tz;
  v_fim_ts := v_fim::timestamp at time zone v_tz;

  -- evolução mensal: ano corrente inteiro, ativos (snapshot no fim do mês) x
  -- novos (criados no mês) — mesma definição de bi_trend_data, não segue o
  -- filtro de período do topo.
  with meses as (
    select generate_series(1, v_mes_atual) as mes
  ),
  bounds as (
    select mes,
           (make_date(v_ano, mes, 1)::timestamp at time zone v_tz) as ini_ts,
           (case when mes = v_mes_atual then (now() at time zone v_tz)
                 else ((make_date(v_ano, mes, 1) + interval '1 month')::timestamp at time zone v_tz) end) as fim_ts
      from meses
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'mes', b.mes,
      'ativos', (select count(*) from "PACIENTE" pc where pc."EMP_PAC" = p_id_emp and pc."ATIVO_PAC" = true and pc."DTCRI_PAC" < b.fim_ts),
      'novos', (select count(*) from "PACIENTE" pc where pc."EMP_PAC" = p_id_emp and pc."DTCRI_PAC" >= b.ini_ts and pc."DTCRI_PAC" < b.fim_ts)
    ) order by b.mes
  ), '[]'::jsonb)
  into v_evolucao
  from bounds b;

  select coalesce(jsonb_agg(
    jsonb_build_object('nome', nome, 'consultas', consultas, 'pacientes', pacientes) order by consultas desc
  ), '[]'::jsonb)
  into v_profissional
  from (
    select pr."NOME_PROF" as nome,
           count(*) as consultas,
           count(distinct c."ID_PAC") as pacientes
      from "CONSULTA" c
      inner join "PROFISSIONAL" pr on pr."ID_PROF" = c."ID_PROF"
      where c."ID_EMP" = p_id_emp and c."DT_CONS" >= v_ini_ts and c."DT_CONS" < v_fim_ts
      group by pr."NOME_PROF"
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object('nome', valor, 'total', total) order by total desc
  ), '[]'::jsonb)
  into v_sexo
  from (
    select coalesce(nullif("SEXO_PAC", ''), 'Não informado') as valor, count(*) as total
      from "PACIENTE"
      where "EMP_PAC" = p_id_emp and "ATIVO_PAC" = true
      group by 1
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object('nome', faixa, 'total', total) order by ordem
  ), '[]'::jsonb)
  into v_faixa_etaria
  from (
    select faixa, ordem, count(*) as total
      from (
        select case
                 when "DTNASC_PAC" is null then 'Não informado'
                 when age(v_hoje, "DTNASC_PAC") < interval '13 years' then '0-12 anos'
                 when age(v_hoje, "DTNASC_PAC") < interval '18 years' then '13-17 anos'
                 when age(v_hoje, "DTNASC_PAC") < interval '30 years' then '18-29 anos'
                 when age(v_hoje, "DTNASC_PAC") < interval '45 years' then '30-44 anos'
                 when age(v_hoje, "DTNASC_PAC") < interval '60 years' then '45-59 anos'
                 else '60+ anos'
               end as faixa,
               case
                 when "DTNASC_PAC" is null then 99
                 when age(v_hoje, "DTNASC_PAC") < interval '13 years' then 1
                 when age(v_hoje, "DTNASC_PAC") < interval '18 years' then 2
                 when age(v_hoje, "DTNASC_PAC") < interval '30 years' then 3
                 when age(v_hoje, "DTNASC_PAC") < interval '45 years' then 4
                 when age(v_hoje, "DTNASC_PAC") < interval '60 years' then 5
                 else 6
               end as ordem
          from "PACIENTE"
          where "EMP_PAC" = p_id_emp and "ATIVO_PAC" = true
      ) t2
      group by faixa, ordem
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object('nome', valor, 'total', total) order by total desc
  ), '[]'::jsonb)
  into v_grupo
  from (
    select coalesce(g."NOME_GRUPO", 'Sem grupo') as valor, count(*) as total
      from "PACIENTE" p
      left join "GRUPO" g on g."ID_GRUPO" = p."ID_GRUPO"
      where p."EMP_PAC" = p_id_emp and p."ATIVO_PAC" = true
      group by 1
  ) t;

  return jsonb_build_object(
    'ano', v_ano,
    'evolucaoMensal', v_evolucao,
    'porProfissional', v_profissional,
    'porSexo', v_sexo,
    'porFaixaEtaria', v_faixa_etaria,
    'porGrupo', v_grupo
  );
end;
$function$;
