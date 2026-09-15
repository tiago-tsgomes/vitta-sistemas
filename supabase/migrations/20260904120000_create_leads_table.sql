create table public."LEADS" (
  "ID_LEAD" uuid primary key default gen_random_uuid(),
  "ID_EMP" uuid not null references public."EMPRESA"("ID_EMP"),
  "NOME_LEAD" text not null,
  "TELEFONE_LEAD" text not null,
  "DTCRI_LEAD" timestamptz not null default now()
);

alter table public."LEADS" enable row level security;

create policy "leads_select" on public."LEADS"
  for select
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "leads_insert" on public."LEADS"
  for insert
  with check (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "leads_update" on public."LEADS"
  for update
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "leads_delete" on public."LEADS"
  for delete
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());
