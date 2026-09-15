-- Adiciona contagem e taxa de agendamento por dimensão (especialidade e
-- profissional) na tela de Leads do BI, além do que já existia (total de
-- leads, convertidos ao bloco e taxa de conversão). Pedido do usuário:
-- os cards "Por especialidade procurada" e "Por profissional" precisam
-- mostrar leads, agendados (com %) e conv. ao bloco (com %) — três dados,
-- não só dois. Reaproveita a mesma regra de segurança (bi_check_access)
-- e a mesma lógica de período de supabase/migrations/20260904190000_bi_leads.sql.
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
      'agendados', agendados,
      'taxaAgendamentoPct', case when total = 0 then null else round(agendados::numeric / total * 100, 1) end,
      'convertidos', convertidos,
      'taxaConversaoPct', case when total = 0 then null else round(convertidos::numeric / total * 100, 1) end
    ) order by total desc
  ), '[]'::jsonb)
  into v_especialidade
  from (
    select coalesce("PROCURA_LEAD", 'Não informado') as especialidade,
           count(*) as total,
           count(*) filter (where "FOI_AGENDADO_LEAD" is true) as agendados,
           count(*) filter (where "ADERIU_BLOCO_LEAD" = 'Sim') as convertidos
      from "LEADS"
      where "ID_EMP" = p_id_emp and "DTCRI_LEAD" >= v_ini_ts and "DTCRI_LEAD" < v_fim_ts
      group by 1
  ) t;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'nome', nome,
      'total', total,
      'agendados', agendados,
      'taxaAgendamentoPct', case when total = 0 then null else round(agendados::numeric / total * 100, 1) end,
      'convertidos', convertidos,
      'taxaConversaoPct', case when total = 0 then null else round(convertidos::numeric / total * 100, 1) end
    ) order by total desc
  ), '[]'::jsonb)
  into v_profissional
  from (
    select pr."NOME_PROF" as nome,
           count(*) as total,
           count(*) filter (where l."FOI_AGENDADO_LEAD" is true) as agendados,
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
