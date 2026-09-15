-- Categoria 2 do roadmap do Financeiro (Vitta BI): gráfico de linhas com a
-- evolução mensal de faturamento/repasse/líquido, a pedido do usuário em
-- 03/09/2026 — desta vez FIXO no ano corrente (não segue o filtro de período
-- do topo da página, ao contrário de bi_financeiro_resumo/por_profissional/
-- por_especialidade). Card fica acima de "Por profissional" em
-- bi/pages/financeiro.html, renderizado com o helper bi/assets/js/charts.js
-- (mesmo componente de linha usado no gráfico "Pacientes" do dashboard).
--
-- Retorna só de janeiro até o mês corrente (não os 12 meses inteiros), para
-- não desenhar uma queda artificial pra zero nos meses futuros que ainda não
-- têm pagamento.
--
-- Mesmo padrão de join/repasse de bi_financeiro_resumo: PAGAMENTO inner join
-- AGENDAMENTO (exclui pagamento órfão) + left join PROFISSIONAL via
-- AGENDAMENTO.PROF_AGD para calcular o repasse (PERC_PROF).

create or replace function public.bi_financeiro_evolucao_anual(p_id_emp uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz constant text := 'America/Sao_Paulo';
  v_hoje date := (now() at time zone v_tz)::date;
  v_ano int := extract(year from v_hoje)::int;
  v_mes_atual int := extract(month from v_hoje)::int;
  result jsonb;
begin
  perform bi_check_access(p_id_emp);

  with meses as (
    select generate_series(1, v_mes_atual) as mes
  ),
  pagamentos as (
    select extract(month from p."DT_PGTO")::int as mes,
           coalesce(sum(p."VL_PGTO"), 0) as recebido,
           coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 0) / 100.0), 0) as repasse
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and p."DT_PGTO" >= make_date(v_ano, 1, 1) and p."DT_PGTO" < make_date(v_ano + 1, 1, 1)
      group by extract(month from p."DT_PGTO")
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'mes', m.mes,
      'recebido', round(coalesce(pg.recebido, 0), 2),
      'repasse', round(coalesce(pg.repasse, 0), 2),
      'liquido', round(coalesce(pg.recebido, 0) - coalesce(pg.repasse, 0), 2)
    ) order by m.mes
  ), '[]'::jsonb)
  into result
  from meses m
  left join pagamentos pg on pg.mes = m.mes;

  return jsonb_build_object('ano', v_ano, 'meses', result);
end;
$$;
