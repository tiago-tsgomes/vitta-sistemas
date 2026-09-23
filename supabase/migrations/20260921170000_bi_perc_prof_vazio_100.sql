-- Vitta BI: PROFISSIONAL.PERC_PROF vazio (ou pagamento sem profissional vinculado) passa a valer 100%,
-- ou seja, a clínica fica com todo o valor (Repasse à Clínica = recebido) e o Líquido dos profissionais é 0.
-- Antes, todas as RPCs abaixo (exceto bi_despesas_*, já ajustadas em 20260921160000) tratavam vazio como 0%.
--
-- Em vez de repetir o corpo de cada função, reescreve a definição atual de cada uma trocando só o
-- fallback do coalesce. CREATE OR REPLACE preserva owner e grants. Idempotente: se já estiver em 100,
-- a definição não muda.
do $mig$
declare
  r record;
  v_def text;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'bi_dashboard_kpis',
         'bi_trend_data',
         'bi_financeiro_resumo',
         'bi_financeiro_por_profissional',
         'bi_financeiro_por_especialidade',
         'bi_financeiro_evolucao_anual',
         'bi_equipe_por_profissional'
       )
  loop
    v_def := pg_get_functiondef(r.oid);
    if v_def like '%coalesce(pr."PERC_PROF", 0)%' then
      execute replace(v_def, 'coalesce(pr."PERC_PROF", 0)', 'coalesce(pr."PERC_PROF", 100)');
      raise notice 'atualizada: %', r.proname;
    end if;
  end loop;
end
$mig$;
