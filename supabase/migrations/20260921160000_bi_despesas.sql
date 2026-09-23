-- Vitta BI — relatório de Despesas (bi/pages/despesas.html), cruzando DESPESA com os recebimentos.
--
-- Regras (todas as RPCs validam o vínculo do usuário com a empresa via bi_check_access, igual ao Financeiro):
--  * Recebido / Repasse à Clínica: PAGAMENTO não estornado × PERC_PROF. Diferente de bi_financeiro_resumo: PERC_PROF vazio (ou sem profissional) conta como 100% (a clínica fica com tudo).
--    "Líquido Profissionais" = recebido − repasse; a receita da clínica é o Repasse à Clínica.
--  * Despesas PAGAS: DESPESA.DTPAG_DESP dentro do período (regime de caixa, comparável ao recebido).
--  * Despesas EM ABERTO: sem DTPAG_DESP e vencimento dentro do período (até o fim do mês/ano nos períodos
--    "mes", "trimestre" e "ano", para enxergar o que ainda vai vencer). VENCIDAS = em aberto com vencimento < hoje.
--  * Resultado líquido = Repasse à Clínica − Despesas pagas. Resultado projetado = Repasse − (pagas + em aberto).

-- ---------------------------------------------------------------------
-- Helper interno: intervalo do período (mesmo vocabulário de bi_financeiro_resumo)
-- ---------------------------------------------------------------------
create or replace function public.bi_periodo_range(
  p_period text,
  p_data_ini date default null,
  p_data_fim date default null,
  out v_ini date,
  out v_fim date,
  out v_ini_ant date,
  out v_fim_ant date,
  out v_fim_venc date
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_dias int;
begin
  if p_period not in ('hoje', 'ontem', '7dias', '30dias', 'mes', 'mes_passado', 'trimestre', 'ano', 'custom') then
    raise exception 'período inválido: %', p_period;
  end if;

  if p_period = 'hoje' then
    v_ini := v_hoje; v_fim := v_hoje + 1; v_ini_ant := v_hoje - 1; v_fim_ant := v_hoje;
  elsif p_period = 'ontem' then
    v_ini := v_hoje - 1; v_fim := v_hoje; v_ini_ant := v_hoje - 2; v_fim_ant := v_hoje - 1;
  elsif p_period = '7dias' then
    v_ini := v_hoje - 6; v_fim := v_hoje + 1; v_ini_ant := v_ini - 7; v_fim_ant := v_ini;
  elsif p_period = '30dias' then
    v_ini := v_hoje - 29; v_fim := v_hoje + 1; v_ini_ant := v_ini - 30; v_fim_ant := v_ini;
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
    v_fim_ant := v_ini;
  elsif p_period = 'trimestre' then
    v_ini := (date_trunc('month', v_hoje) - interval '2 month')::date;
    v_fim := v_hoje + 1;
    v_ini_ant := (date_trunc('month', v_hoje) - interval '5 month')::date;
    v_fim_ant := v_ini;
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

  -- Limite superior para o que ainda VAI vencer: fim do mês (mes/trimestre) ou do ano (ano)
  v_fim_venc := case
    when p_period in ('mes', 'trimestre') then (date_trunc('month', v_hoje) + interval '1 month')::date
    when p_period = 'ano' then (date_trunc('year', v_hoje) + interval '1 year')::date
    else v_fim
  end;
end;
$$;

revoke all on function public.bi_periodo_range(text, date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Resumo: KPIs de despesas + vínculo com recebimento (resultado líquido)
-- ---------------------------------------------------------------------
create or replace function public.bi_despesas_resumo(
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
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r record;

  v_recebido numeric; v_repasse numeric;
  v_recebido_ant numeric; v_repasse_ant numeric;

  v_pagas numeric; v_qtd_pagas bigint; v_pagas_ant numeric;
  v_aberto numeric; v_qtd_aberto bigint;
  v_venc numeric; v_qtd_venc bigint;
  v_lanc numeric; v_qtd_lanc bigint;
  v_fixas numeric; v_parc numeric; v_avul numeric;

  v_res numeric; v_res_ant numeric;
begin
  perform bi_check_access(p_id_emp);
  select * into r from bi_periodo_range(p_period, p_data_ini, p_data_fim);

  select coalesce(sum(p."VL_PGTO"), 0),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 100) / 100.0), 0)
    into v_recebido, v_repasse
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and p."DT_PGTO" >= r.v_ini and p."DT_PGTO" < r.v_fim;

  select coalesce(sum(p."VL_PGTO"), 0),
         coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 100) / 100.0), 0)
    into v_recebido_ant, v_repasse_ant
    from "PAGAMENTO" p
    inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
    left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
    where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
      and p."DT_PGTO" >= r.v_ini_ant and p."DT_PGTO" < r.v_fim_ant;

  select coalesce(sum("VALOR_DESP"), 0), count(*)
    into v_pagas, v_qtd_pagas
    from "DESPESA"
    where "ID_EMP" = p_id_emp and "DTPAG_DESP" >= r.v_ini and "DTPAG_DESP" < r.v_fim;

  select coalesce(sum("VALOR_DESP"), 0)
    into v_pagas_ant
    from "DESPESA"
    where "ID_EMP" = p_id_emp and "DTPAG_DESP" >= r.v_ini_ant and "DTPAG_DESP" < r.v_fim_ant;

  select coalesce(sum("VALOR_DESP"), 0), count(*),
         coalesce(sum("VALOR_DESP") filter (where "DTVENC_DESP" < v_hoje), 0),
         count(*) filter (where "DTVENC_DESP" < v_hoje)
    into v_aberto, v_qtd_aberto, v_venc, v_qtd_venc
    from "DESPESA"
    where "ID_EMP" = p_id_emp and "DTPAG_DESP" is null
      and "DTVENC_DESP" >= r.v_ini and "DTVENC_DESP" < r.v_fim_venc;

  select coalesce(sum("VALOR_DESP"), 0), count(*),
         coalesce(sum("VALOR_DESP") filter (where "REC_DESP" = 'FIXA'), 0),
         coalesce(sum("VALOR_DESP") filter (where "REC_DESP" = 'REPETIR'), 0),
         coalesce(sum("VALOR_DESP") filter (where "REC_DESP" = 'UNICA'), 0)
    into v_lanc, v_qtd_lanc, v_fixas, v_parc, v_avul
    from "DESPESA"
    where "ID_EMP" = p_id_emp
      and "DTVENC_DESP" >= r.v_ini and "DTVENC_DESP" < r.v_fim_venc;

  v_res := v_repasse - v_pagas;
  v_res_ant := v_repasse_ant - v_pagas_ant;

  return jsonb_build_object(
    'recebido', round(v_recebido, 2),
    'liquidoProf', round(v_recebido - v_repasse, 2),
    'repasseClinica', round(v_repasse, 2),
    'repasseDeltaPct', case when v_repasse_ant = 0 then null else round((v_repasse - v_repasse_ant) / v_repasse_ant * 100, 1) end,

    'despesasPagas', round(v_pagas, 2),
    'despesasPagasQtd', v_qtd_pagas,
    'despesasPagasDeltaPct', case when v_pagas_ant = 0 then null else round((v_pagas - v_pagas_ant) / v_pagas_ant * 100, 1) end,

    'resultado', round(v_res, 2),
    'resultadoDeltaPct', case when v_res_ant = 0 then null else round((v_res - v_res_ant) / abs(v_res_ant) * 100, 1) end,
    'margemPct', case when v_repasse = 0 then null else round(v_res / v_repasse * 100, 1) end,
    'comprometimentoPct', case when v_repasse = 0 then null else round(v_pagas / v_repasse * 100, 1) end,

    'abertas', round(v_aberto, 2),
    'abertasQtd', v_qtd_aberto,
    'vencidas', round(v_venc, 2),
    'vencidasQtd', v_qtd_venc,
    'aVencer', round(v_aberto - v_venc, 2),
    'resultadoProjetado', round(v_repasse - v_pagas - v_aberto, 2),

    'lancado', round(v_lanc, 2),
    'lancadoQtd', v_qtd_lanc,
    'fixas', round(v_fixas, 2),
    'parceladas', round(v_parc, 2),
    'avulsas', round(v_avul, 2)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Por categoria e por forma de pagamento
-- ---------------------------------------------------------------------
create or replace function public.bi_despesas_por_categoria(
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
  r record;
  v_cats jsonb;
  v_formas jsonb;
begin
  perform bi_check_access(p_id_emp);
  select * into r from bi_periodo_range(p_period, p_data_ini, p_data_fim);

  with pag as (
    select "ID_CATDESP" as id_cat, sum("VALOR_DESP") as pago, count(*) as qtd
      from "DESPESA"
      where "ID_EMP" = p_id_emp and "DTPAG_DESP" >= r.v_ini and "DTPAG_DESP" < r.v_fim
      group by "ID_CATDESP"
  ),
  abe as (
    select "ID_CATDESP" as id_cat, sum("VALOR_DESP") as aberto, count(*) as qtd
      from "DESPESA"
      where "ID_EMP" = p_id_emp and "DTPAG_DESP" is null
        and "DTVENC_DESP" >= r.v_ini and "DTVENC_DESP" < r.v_fim_venc
      group by "ID_CATDESP"
  ),
  ant as (
    select "ID_CATDESP" as id_cat, sum("VALOR_DESP") as pago
      from "DESPESA"
      where "ID_EMP" = p_id_emp and "DTPAG_DESP" >= r.v_ini_ant and "DTPAG_DESP" < r.v_fim_ant
      group by "ID_CATDESP"
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c."ID_CATDESP",
      'nome', c."NOME_CATDESP",
      'icone', c."ICONE_CATDESP",
      'cor', c."COR_CATDESP",
      'pago', round(coalesce(pag.pago, 0), 2),
      'aberto', round(coalesce(abe.aberto, 0), 2),
      'total', round(coalesce(pag.pago, 0) + coalesce(abe.aberto, 0), 2),
      'qtd', coalesce(pag.qtd, 0) + coalesce(abe.qtd, 0),
      'deltaPct', case when coalesce(ant.pago, 0) = 0 then null
                  else round((coalesce(pag.pago, 0) - ant.pago) / ant.pago * 100, 1) end
    ) order by coalesce(pag.pago, 0) + coalesce(abe.aberto, 0) desc
  ), '[]'::jsonb)
  into v_cats
  from "CATDESP" c
  left join pag on pag.id_cat = c."ID_CATDESP"
  left join abe on abe.id_cat = c."ID_CATDESP"
  left join ant on ant.id_cat = c."ID_CATDESP"
  where c."ID_EMP" = p_id_emp
    and coalesce(pag.pago, 0) + coalesce(abe.aberto, 0) > 0;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'nome', f.nome,
      'pago', round(f.pago, 2),
      'aberto', round(f.aberto, 2),
      'total', round(f.pago + f.aberto, 2)
    ) order by f.pago + f.aberto desc
  ), '[]'::jsonb)
  into v_formas
  from (
    select coalesce(t."NOME_TIPPAG", 'Não informada') as nome,
           coalesce(sum(d."VALOR_DESP") filter (
             where d."DTPAG_DESP" >= r.v_ini and d."DTPAG_DESP" < r.v_fim), 0) as pago,
           coalesce(sum(d."VALOR_DESP") filter (
             where d."DTPAG_DESP" is null
               and d."DTVENC_DESP" >= r.v_ini and d."DTVENC_DESP" < r.v_fim_venc), 0) as aberto
      from "DESPESA" d
      left join "TIPPAG" t on t."ID_TIPPAG" = d."ID_TIPPAG" and t."ID_EMP" = p_id_emp
      where d."ID_EMP" = p_id_emp
      group by coalesce(t."NOME_TIPPAG", 'Não informada')
  ) f
  where f.pago + f.aberto > 0;

  return jsonb_build_object('categorias', v_cats, 'formasPagamento', v_formas);
end;
$$;

-- ---------------------------------------------------------------------
-- Evolução do ano corrente (12 meses): recebimento x despesas x resultado
-- ---------------------------------------------------------------------
create or replace function public.bi_despesas_evolucao(p_id_emp uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ano int := extract(year from v_hoje)::int;
  v_ini date := make_date(extract(year from v_hoje)::int, 1, 1);
  v_fim date := make_date(extract(year from v_hoje)::int + 1, 1, 1);
  result jsonb;
begin
  perform bi_check_access(p_id_emp);

  with meses as (
    select generate_series(1, 12) as mes
  ),
  pg as (
    select extract(month from p."DT_PGTO")::int as mes,
           coalesce(sum(p."VL_PGTO"), 0) as recebido,
           coalesce(sum(p."VL_PGTO" * coalesce(pr."PERC_PROF", 100) / 100.0), 0) as repasse
      from "PAGAMENTO" p
      inner join "AGENDAMENTO" a on a."ID_AGD" = p."ID_AGD" and a."ID_EMP" = p_id_emp
      left join "PROFISSIONAL" pr on pr."ID_PROF" = a."PROF_AGD"
      where p."ID_EMP" = p_id_emp and p."ESTORNADO_PGTO" is not true
        and p."DT_PGTO" >= v_ini and p."DT_PGTO" < v_fim
      group by 1
  ),
  dp as (
    select extract(month from "DTPAG_DESP")::int as mes, sum("VALOR_DESP") as pagas
      from "DESPESA"
      where "ID_EMP" = p_id_emp and "DTPAG_DESP" >= v_ini and "DTPAG_DESP" < v_fim
      group by 1
  ),
  dl as (
    select extract(month from "DTVENC_DESP")::int as mes,
           sum("VALOR_DESP") as lancado,
           coalesce(sum("VALOR_DESP") filter (where "DTPAG_DESP" is null), 0) as abertas
      from "DESPESA"
      where "ID_EMP" = p_id_emp and "DTVENC_DESP" >= v_ini and "DTVENC_DESP" < v_fim
      group by 1
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'mes', m.mes,
      'recebido', round(coalesce(pg.recebido, 0), 2),
      'repasse', round(coalesce(pg.repasse, 0), 2),
      'pagas', round(coalesce(dp.pagas, 0), 2),
      'abertas', round(coalesce(dl.abertas, 0), 2),
      'lancado', round(coalesce(dl.lancado, 0), 2),
      'resultado', round(coalesce(pg.repasse, 0) - coalesce(dp.pagas, 0), 2)
    ) order by m.mes
  ), '[]'::jsonb)
  into result
  from meses m
  left join pg on pg.mes = m.mes
  left join dp on dp.mes = m.mes
  left join dl on dl.mes = m.mes;

  return jsonb_build_object('ano', v_ano, 'mesAtual', extract(month from v_hoje)::int, 'meses', result);
end;
$$;

-- ---------------------------------------------------------------------
-- Lançamentos do período (para tabela, maiores despesas e contas em aberto)
-- ---------------------------------------------------------------------
create or replace function public.bi_despesas_lancamentos(
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
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r record;
  v_itens jsonb;
  v_total bigint;
begin
  perform bi_check_access(p_id_emp);
  select * into r from bi_periodo_range(p_period, p_data_ini, p_data_fim);

  select count(*) into v_total
    from "DESPESA" d
    where d."ID_EMP" = p_id_emp
      and ((d."DTVENC_DESP" >= r.v_ini and d."DTVENC_DESP" < r.v_fim_venc)
        or (d."DTPAG_DESP" >= r.v_ini and d."DTPAG_DESP" < r.v_fim));

  select coalesce(jsonb_agg(x.item order by x.venc, x.descr), '[]'::jsonb)
  into v_itens
  from (
    select d."DTVENC_DESP" as venc, d."DESCR_DESP" as descr,
           jsonb_build_object(
             'id', d."ID_DESP",
             'descricao', d."DESCR_DESP",
             'categoria', c."NOME_CATDESP",
             'cor', c."COR_CATDESP",
             'icone', c."ICONE_CATDESP",
             'forma', t."NOME_TIPPAG",
             'valor', d."VALOR_DESP",
             'vencimento', d."DTVENC_DESP",
             'pagamento', d."DTPAG_DESP",
             'recorrencia', d."REC_DESP",
             'parcela', d."PARCELA_DESP",
             'totalParcelas', d."TOTAL_PARC_DESP",
             'status', case
               when d."DTPAG_DESP" is not null then 'pago'
               when d."DTVENC_DESP" < v_hoje then 'vencida'
               else 'aVencer' end
           ) as item
      from "DESPESA" d
      left join "CATDESP" c on c."ID_CATDESP" = d."ID_CATDESP" and c."ID_EMP" = p_id_emp
      left join "TIPPAG" t on t."ID_TIPPAG" = d."ID_TIPPAG" and t."ID_EMP" = p_id_emp
      where d."ID_EMP" = p_id_emp
        and ((d."DTVENC_DESP" >= r.v_ini and d."DTVENC_DESP" < r.v_fim_venc)
          or (d."DTPAG_DESP" >= r.v_ini and d."DTPAG_DESP" < r.v_fim))
      order by d."DTVENC_DESP", d."DESCR_DESP"
      limit 500
  ) x;

  return jsonb_build_object('total', v_total, 'itens', v_itens);
end;
$$;

revoke all on function public.bi_despesas_resumo(uuid, text, date, date) from public, anon;
revoke all on function public.bi_despesas_por_categoria(uuid, text, date, date) from public, anon;
revoke all on function public.bi_despesas_evolucao(uuid) from public, anon;
revoke all on function public.bi_despesas_lancamentos(uuid, text, date, date) from public, anon;
grant execute on function public.bi_despesas_resumo(uuid, text, date, date) to authenticated;
grant execute on function public.bi_despesas_por_categoria(uuid, text, date, date) to authenticated;
grant execute on function public.bi_despesas_evolucao(uuid) to authenticated;
grant execute on function public.bi_despesas_lancamentos(uuid, text, date, date) to authenticated;
