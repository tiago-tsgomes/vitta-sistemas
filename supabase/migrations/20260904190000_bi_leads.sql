-- RPCs do Vitta BI para a tela de Leads (bi/pages/leads.html).
-- Mesma regra inegociável das demais RPCs do BI: nunca consulta direta às
-- tabelas transacionais nem filtro client-side de empresa — todo cálculo
-- passa por bi_check_access(p_id_emp) antes de ler qualquer linha
-- (ver Documentos/escopo-vitta-bi.md e bi_financeiro_resumo/_por_profissional
-- em supabase/migrations/20260903*.sql, que seguem o mesmo padrão).

-- KPIs (cards do topo) + funil de conversão, com comparação ao período
-- equivalente imediatamente anterior (mesma lógica de datas de
-- bi_financeiro_resumo, reaproveitada aqui para os mesmos presets de período).
create or replace function public.bi_leads_resumo(
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

  v_total bigint; v_total_ant bigint;
  v_agendados bigint; v_agendados_ant bigint;
  v_bloco bigint; v_bloco_ant bigint;
  v_desistencia bigint; v_desistencia_ant bigint;
  v_sem_prof bigint; v_sem_prof_ant bigint;

  v_taxa_agendamento numeric; v_taxa_agendamento_ant numeric;
  v_taxa_bloco numeric; v_taxa_bloco_ant numeric;
  v_taxa_bloco_sobre_agendados numeric; v_taxa_bloco_sobre_agendados_ant numeric;
  v_taxa_desistencia numeric; v_taxa_desistencia_ant numeric;
  v_taxa_sem_prof numeric; v_taxa_sem_prof_ant numeric;
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

  select count(*),
         count(*) filter (where "FOI_AGENDADO_LEAD" is true),
         count(*) filter (where "ADERIU_BLOCO_LEAD" = 'Sim'),
         count(*) filter (where "DESISTENCIA_LEAD" is not null),
         count(*) filter (where "ID_PROF" is null)
    into v_total, v_agendados, v_bloco, v_desistencia, v_sem_prof
    from "LEADS"
    where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts;

  select count(*),
         count(*) filter (where "FOI_AGENDADO_LEAD" is true),
         count(*) filter (where "ADERIU_BLOCO_LEAD" = 'Sim'),
         count(*) filter (where "DESISTENCIA_LEAD" is not null),
         count(*) filter (where "ID_PROF" is null)
    into v_total_ant, v_agendados_ant, v_bloco_ant, v_desistencia_ant, v_sem_prof_ant
    from "LEADS"
    where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ant_ts and "DTCRI_LEAD" < v_fim_ant_ts;

  v_taxa_agendamento := case when v_total = 0 then null else round(v_agendados::numeric / v_total * 100, 1) end;
  v_taxa_agendamento_ant := case when v_total_ant = 0 then null else round(v_agendados_ant::numeric / v_total_ant * 100, 1) end;

  v_taxa_bloco := case when v_total = 0 then null else round(v_bloco::numeric / v_total * 100, 1) end;
  v_taxa_bloco_ant := case when v_total_ant = 0 then null else round(v_bloco_ant::numeric / v_total_ant * 100, 1) end;

  v_taxa_bloco_sobre_agendados := case when v_agendados = 0 then null else round(v_bloco::numeric / v_agendados * 100, 1) end;
  v_taxa_bloco_sobre_agendados_ant := case when v_agendados_ant = 0 then null else round(v_bloco_ant::numeric / v_agendados_ant * 100, 1) end;

  v_taxa_desistencia := case when v_total = 0 then null else round(v_desistencia::numeric / v_total * 100, 1) end;
  v_taxa_desistencia_ant := case when v_total_ant = 0 then null else round(v_desistencia_ant::numeric / v_total_ant * 100, 1) end;

  v_taxa_sem_prof := case when v_total = 0 then null else round(v_sem_prof::numeric / v_total * 100, 1) end;
  v_taxa_sem_prof_ant := case when v_total_ant = 0 then null else round(v_sem_prof_ant::numeric / v_total_ant * 100, 1) end;

  return jsonb_build_object(
    'totalLeads', v_total,
    'totalLeadsDeltaPct', case when v_total_ant = 0 then null else round((v_total - v_total_ant)::numeric / v_total_ant * 100, 1) end,

    'taxaAgendamentoPct', v_taxa_agendamento,
    'taxaAgendamentoDeltaPct', case when v_taxa_agendamento is null or v_taxa_agendamento_ant is null then null else round(v_taxa_agendamento - v_taxa_agendamento_ant, 1) end,

    'taxaConversaoBlocoPct', v_taxa_bloco,
    'taxaConversaoBlocoDeltaPct', case when v_taxa_bloco is null or v_taxa_bloco_ant is null then null else round(v_taxa_bloco - v_taxa_bloco_ant, 1) end,

    'taxaConversaoSobreAgendadosPct', v_taxa_bloco_sobre_agendados,
    'taxaConversaoSobreAgendadosDeltaPct', case when v_taxa_bloco_sobre_agendados is null or v_taxa_bloco_sobre_agendados_ant is null then null else round(v_taxa_bloco_sobre_agendados - v_taxa_bloco_sobre_agendados_ant, 1) end,

    'taxaDesistenciaPct', v_taxa_desistencia,
    'taxaDesistenciaDeltaPct', case when v_taxa_desistencia is null or v_taxa_desistencia_ant is null then null else round(v_taxa_desistencia - v_taxa_desistencia_ant, 1) end,

    'semProfissionalCount', v_sem_prof,
    'semProfissionalPct', v_taxa_sem_prof,
    'semProfissionalDeltaPct', case when v_taxa_sem_prof is null or v_taxa_sem_prof_ant is null then null else round(v_taxa_sem_prof - v_taxa_sem_prof_ant, 1) end,

    'funil', jsonb_build_object(
      'criados', v_total,
      'agendados', v_agendados,
      'aderiuBloco', v_bloco
    )
  );
end;
$function$;

-- Gráficos por dimensão: evolução mensal, especialidade (PROCURA_LEAD),
-- profissional, abordagem, distribuição de ADERIU_BLOCO e motivos de
-- desistência. Segue o filtro de período do topo (menos a evolução mensal,
-- que mostra o ano corrente inteiro, igual a bi_financeiro_evolucao_anual).
create or replace function public.bi_leads_por_dimensao(
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
  v_dias int;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;

  v_evolucao jsonb;
  v_especialidade jsonb;
  v_profissional jsonb;
  v_abordagem jsonb;
  v_aderiu_bloco jsonb;
  v_desistencia jsonb;
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

  -- evolução mensal: ano corrente inteiro, não segue o filtro de período do topo
  with meses as (
    select generate_series(1, v_mes_atual) as mes
  ),
  leads_mes as (
    select extract(month from ("DTCRI_LEAD" at time zone v_tz))::int as mes,
           count(*) as total,
           count(*) filter (where "ADERIU_BLOCO_LEAD" = 'Sim') as convertidos
      from "LEADS"
      where "ID_EMP" = p_id_emp
        and "DTCRI_LEAD" >= (make_date(v_ano, 1, 1)::timestamp at time zone v_tz)
        and "DTCRI_LEAD" < (make_date(v_ano + 1, 1, 1)::timestamp at time zone v_tz)
      group by 1
  )
  select coalesce(jsonb_agg(
    jsonb_build_object('mes', m.mes, 'total', coalesce(lm.total, 0), 'convertidos', coalesce(lm.convertidos, 0))
    order by m.mes
  ), '[]'::jsonb)
  into v_evolucao
  from meses m
  left join leads_mes lm on lm.mes = m.mes;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'nome', especialidade,
      'total', total,
      'convertidos', convertidos,
      'taxaConversaoPct', case when total = 0 then null else round(convertidos::numeric / total * 100, 1) end
    ) order by total desc
  ), '[]'::jsonb)
  into v_especialidade
  from (
    select coalesce("PROCURA_LEAD", 'Não informado') as especialidade,
           count(*) as total,
           count(*) filter (where "ADERIU_BLOCO_LEAD" = 'Sim') as convertidos
      from "LEADS"
      where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts
      group by 1
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'nome', nome,
      'total', total,
      'convertidos', convertidos,
      'taxaConversaoPct', case when total = 0 then null else round(convertidos::numeric / total * 100, 1) end
    ) order by total desc
  ), '[]'::jsonb)
  into v_profissional
  from (
    select pr."NOME_PROF" as nome,
           count(*) as total,
           count(*) filter (where l."ADERIU_BLOCO_LEAD" = 'Sim') as convertidos
      from "LEADS" l
      inner join "PROFISSIONAL" pr on pr."ID_PROF" = l."ID_PROF"
      where l."ID_EMP" = p_id_emp and l."DTCRI_LEAD" >= v_ini_ts and l."DTCRI_LEAD" < v_fim_ts
      group by pr."NOME_PROF"
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'nome', abordagem,
      'total', total,
      'convertidos', convertidos,
      'taxaConversaoPct', case when total = 0 then null else round(convertidos::numeric / total * 100, 1) end
    ) order by total desc
  ), '[]'::jsonb)
  into v_abordagem
  from (
    select coalesce("ABORDAGEM_LEAD", 'Não informado') as abordagem,
           count(*) as total,
           count(*) filter (where "ADERIU_BLOCO_LEAD" = 'Sim') as convertidos
      from "LEADS"
      where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts
      group by 1
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object('nome', valor, 'total', total) order by total desc
  ), '[]'::jsonb)
  into v_aderiu_bloco
  from (
    select coalesce("ADERIU_BLOCO_LEAD", 'Não informado') as valor, count(*) as total
      from "LEADS"
      where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts
      group by 1
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object('nome', motivo, 'total', total) order by total desc
  ), '[]'::jsonb)
  into v_desistencia
  from (
    select "DESISTENCIA_LEAD" as motivo, count(*) as total
      from "LEADS"
      where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts
        and "DESISTENCIA_LEAD" is not null
      group by 1
  ) t;

  return jsonb_build_object(
    'ano', v_ano,
    'evolucaoMensal', v_evolucao,
    'porEspecialidade', v_especialidade,
    'porProfissional', v_profissional,
    'porAbordagem', v_abordagem,
    'distribuicaoAderiuBloco', v_aderiu_bloco,
    'motivosDesistencia', v_desistencia
  );
end;
$function$;
