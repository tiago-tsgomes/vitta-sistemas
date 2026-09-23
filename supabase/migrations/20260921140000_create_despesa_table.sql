-- Despesas (módulo Despesas).
-- Pago = DTPAG_DESP preenchida. Recorrência: UNICA (avulsa), FIXA (mensal, gerada 12 meses à frente)
-- ou REPETIR (mensal, N parcelas). Séries compartilham ID_SERIE_DESP; cada lançamento é uma linha própria.

-- Permite FK composta (categoria precisa ser da mesma empresa da despesa)
alter table public."CATDESP" add constraint "CATDESP_id_emp_uq" unique ("ID_CATDESP", "ID_EMP");

create table public."DESPESA" (
  "ID_DESP" uuid primary key default gen_random_uuid(),
  "ID_EMP" uuid not null references public."EMPRESA"("ID_EMP"),
  "ID_CATDESP" uuid not null,
  "ID_TIPPAG" uuid references public."TIPPAG"("ID_TIPPAG") on delete set null,
  "DESCR_DESP" text not null check (char_length(btrim("DESCR_DESP")) between 1 and 120),
  "VALOR_DESP" numeric(12,2) not null check ("VALOR_DESP" > 0),
  "DTVENC_DESP" date not null,
  "DTPAG_DESP" date,
  "OBS_DESP" text check (char_length("OBS_DESP") <= 500),
  "REC_DESP" text not null default 'UNICA' check ("REC_DESP" in ('UNICA', 'FIXA', 'REPETIR')),
  "ID_SERIE_DESP" uuid,
  "PARCELA_DESP" int check ("PARCELA_DESP" >= 1),
  "TOTAL_PARC_DESP" int check ("TOTAL_PARC_DESP" >= 2),
  "DTCRI_DESP" timestamptz not null default now(),
  constraint "DESPESA_catdesp_fk" foreign key ("ID_CATDESP", "ID_EMP")
    references public."CATDESP"("ID_CATDESP", "ID_EMP") on delete restrict,
  constraint "DESPESA_serie_ck" check (
    ("REC_DESP" = 'UNICA' and "ID_SERIE_DESP" is null and "PARCELA_DESP" is null and "TOTAL_PARC_DESP" is null)
    or ("REC_DESP" = 'FIXA' and "ID_SERIE_DESP" is not null and "PARCELA_DESP" is not null and "TOTAL_PARC_DESP" is null)
    or ("REC_DESP" = 'REPETIR' and "ID_SERIE_DESP" is not null and "PARCELA_DESP" is not null and "TOTAL_PARC_DESP" is not null)
  )
);

create index "DESPESA_emp_venc_idx" on public."DESPESA" ("ID_EMP", "DTVENC_DESP");
create index "DESPESA_serie_idx" on public."DESPESA" ("ID_SERIE_DESP", "PARCELA_DESP") where "ID_SERIE_DESP" is not null;
create index "DESPESA_catdesp_idx" on public."DESPESA" ("ID_CATDESP");

create trigger prevent_reassign
  before update on public."DESPESA"
  for each row execute function prevent_tenant_reassignment('ID_EMP');

alter table public."DESPESA" enable row level security;

create policy "despesa_select" on public."DESPESA"
  for select
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "despesa_insert" on public."DESPESA"
  for insert
  with check (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
  );

create policy "despesa_update" on public."DESPESA"
  for update
  using (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
  );

create policy "despesa_delete" on public."DESPESA"
  for delete
  using (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
  );

revoke all on public."DESPESA" from anon;
