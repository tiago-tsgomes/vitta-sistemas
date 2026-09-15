-- Categoria 4 do roadmap do Financeiro (Vitta BI): ranking por especialidade,
-- a pedido do usuário em 03/09/2026 — mesmo card/layout de
-- bi_financeiro_por_profissional (categoria 3), mas agrupado por
-- PROFISSIONAL.ID_ESPEC (dado estruturado, tabela ESPECIALIDADE) em vez de
-- por profissional individual. Fica logo abaixo do card "Por profissional"
-- em bi/pages/financeiro.html.
--
-- Mesmas janelas de comparação e vocabulário de p_period de
-- bi_financeiro_por_profissional/bi_financeiro_resumo (hoje, ontem, 7dias,
-- 30dias, mes, mes_passado, trimestre, ano, custom). LY (recebidoDeltaPctLY)
-- é sempre v_ini/v_fim deslocados em 1 ano, LM (recebidoDeltaPctLM) é o
-- intervalo equivalente imediatamente anterior.
--
-- Profissionais sem ID_ESPEC caem no grupo "Sem especialidade" (join
-- null-safe com "is not distinct from"). Atribuição de profissional/
-- especialidade sempre via AGENDAMENTO.PROF_AGD -> PROFISSIONAL.ID_ESPEC,
-- nunca PAGAMENTO.ID_PROF direto (mesmo padrão das categorias 1 e 3).

create or replace function public.bi_financeiro_por_especialidade(
  p_id_emp uuid,
  p_period text default 'mes',
  p_data_ini date default null,
  p_data_fim date default null
)
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
  v_ini_ly date;
  v_fim_ly date;
  v_dias int;

  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  v_ini_ant_ts timestamptz;
  v_fim_ant_ts timestamptz;

  result jsonb;
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

  v_ini_ly := (v_ini - interval '1 year')::date;
  v_fim_ly := (v_fim - interval '1 year')::date;

  v_ini_ts := v_ini::timestamp at time zone v_tz;
  v_fim_ts := v_fim::timestamp at time zone v_tz;
  v_ini_ant_ts := v_ini_ant::timestamp at time zone v_tz;
  v_fim_ant_ts := v_fim_ant::timestamp at time zone v_tz;

  with base_especialidades as (
    select pr."ID_ESPEC" as id_espec, count(*) as qtd_prof
      from "PROFISSIONAL" pr
      where pr."ID_EMP" = p_id_emp and pr."ATIVO_PROF" is true
      group by pr."ID_ESPEC"
  ),
  atual as (
    select pr."ID_ESPEC" as id_espec,
           coalesce(sum(p."VL_PGTO"), 0) as recebido,
           coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0) as repasse
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and a."PROF_AGD" is not null
        and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim
      group by pr."ID_ESPEC"
  ),
  anterior as (
    select pr."ID_ESPEC" as id_espec,
           coalesce(sum(p."VL_PGTO"), 0) as recebido
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and a."PROF_AGD" is not null
        and p."DT_PGTO" >= v_ini_ant and p."DT_PGTO" < v_fim_ant
      group by pr."ID_ESPEC"
  ),
  ano_anterior as (
    select pr."ID_ESPEC" as id_espec,
           coalesce(sum(p."VL_PGTO"), 0) as recebido
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and a."PROF_AGD" is not null
        and p."DT_PGTO" >= v_ini_ly and p."DT_PGTO" < v_fim_ly
      group by pr."ID_ESPEC"
  ),
  agd_atual as (
    select pr."ID_ESPEC" as id_espec,
           count(*) filter (where a."STATUS_AGD" = 'REALIZADA') as realizadas,
           count(*) filter (where a."STATUS_AGD" = 'FALTA') as faltas
      from "AGENDAMENTO" a
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where a."ID_EMP" = p_id_emp and a."PROF_AGD" is not null
        and a."DT_AGD" >= v_ini_ts and a."DT_AGD" < v_fim_ts
      group by pr."ID_ESPEC"
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', be.id_espec,
      'nome', coalesce(esp."NOME_ESPEC", 'Sem especialidade'),
      'qtdProfissionais', be.qtd_prof,
      'recebido', round(coalesce(at.recebido, 0), 2),
      'recebidoDeltaPctLM', case when coalesce(an.recebido, 0) = 0 then null
                             else round((coalesce(at.recebido, 0) - an.recebido) / an.recebido * 100, 1) end,
      'recebidoDeltaPctLY', case when coalesce(ly.recebido, 0) = 0 then null
                             else round((coalesce(at.recebido, 0) - ly.recebido) / ly.recebido * 100, 1) end,
      'repasseClinica', round(coalesce(at.repasse, 0), 2),
      'liquidoProf', round(coalesce(at.recebido, 0) - coalesce(at.repasse, 0), 2),
      'ticketMedio', case when coalesce(ag.realizadas, 0) = 0 then 0
                      else round(coalesce(at.recebido, 0) / ag.realizadas, 2) end,
      'realizadas', coalesce(ag.realizadas, 0),
      'faltas', coalesce(ag.faltas, 0),
      'taxaFaltaPct', case when (coalesce(ag.realizadas, 0) + coalesce(ag.faltas, 0)) = 0 then null
                       else round(coalesce(ag.faltas, 0)::numeric / (coalesce(ag.realizadas, 0) + coalesce(ag.faltas, 0)) * 100, 1) end
    ) order by coalesce(at.recebido, 0) desc
  ), '[]'::jsonb)
  into result
  from base_especialidades be
  left join "ESPECIALIDADE" esp on esp."ID_ESPEC" = be.id_espec
  left join atual at on at.id_espec is not distinct from be.id_espec
  left join anterior an on an.id_espec is not distinct from be.id_espec
  left join ano_anterior ly on ly.id_espec is not distinct from be.id_espec
  left join agd_atual ag on ag.id_espec is not distinct from be.id_espec;

  return jsonb_build_object('especialidades', result);
end;
$$;
