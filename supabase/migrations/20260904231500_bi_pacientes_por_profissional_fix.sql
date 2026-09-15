-- Corrige o card "Por profissional" da tela Pacientes BI: antes usava CONSULTA
-- filtrada por período (shape {nome, consultas, pacientes}), inconsistente com
-- os cards irmãos (porSexo/porFaixaEtaria/porGrupo), que usam a base ativa de
-- pacientes sem filtro de período. Agora usa PACIENTE_PROFISSIONAL para contar
-- pacientes ativos vinculados a cada profissional, no mesmo shape {nome, total}.

CREATE OR REPLACE FUNCTION public.bi_pacientes_por_dimensao(p_id_emp uuid, p_period text DEFAULT 'mes'::text, p_data_ini date DEFAULT NULL::date, p_data_fim date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- por profissional: base ativa de pacientes vinculados (PACIENTE_PROFISSIONAL),
  -- não segue o filtro de período do topo — mesmo padrão de porSexo/porFaixaEtaria/porGrupo.
  select coalesce(jsonb_agg(
    jsonb_build_object('nome', nome, 'total', total) order by total desc
  ), '[]'::jsonb)
  into v_profissional
  from (
    select pr."NOME_PROF" as nome, count(distinct pp."PAC_ID") as total
      from "PACIENTE_PROFISSIONAL" pp
      inner join "PACIENTE" p on p."ID_PAC" = pp."PAC_ID" and p."EMP_PAC" = p_id_emp and p."ATIVO_PAC" = true
      inner join "PROFISSIONAL" pr on pr."ID_PROF" = pp."PROF_ID" and pr."ID_EMP" = p_id_emp and pr."ATIVO_PROF" = true
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
$function$
