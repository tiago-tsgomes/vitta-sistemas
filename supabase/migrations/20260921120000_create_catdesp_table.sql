-- Categorias de despesa (módulo Despesas). Sem categorias padrão: cada empresa cadastra as suas.
create table public."CATDESP" (
  "ID_CATDESP" uuid primary key default gen_random_uuid(),
  "ID_EMP" uuid not null references public."EMPRESA"("ID_EMP"),
  "NOME_CATDESP" text not null check (char_length(btrim("NOME_CATDESP")) between 1 and 60),
  "ICONE_CATDESP" text not null default 'more',
  "COR_CATDESP" text not null default '#2ABCD4' check ("COR_CATDESP" ~ '^#[0-9A-Fa-f]{6}$'),
  "DTCRI_CATDESP" timestamptz not null default now()
);

-- Nome único por empresa (sem diferenciar maiúsculas/minúsculas)
create unique index "CATDESP_emp_nome_uq" on public."CATDESP" ("ID_EMP", lower(btrim("NOME_CATDESP")));

create trigger prevent_reassign
  before update on public."CATDESP"
  for each row execute function prevent_tenant_reassignment('ID_EMP');

alter table public."CATDESP" enable row level security;

create policy "catdesp_select" on public."CATDESP"
  for select
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "catdesp_insert" on public."CATDESP"
  for insert
  with check (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
  );

create policy "catdesp_update" on public."CATDESP"
  for update
  using (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
  );

create policy "catdesp_delete" on public."CATDESP"
  for delete
  using (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
  );

-- Tabela só é acessada por usuários logados
revoke all on public."CATDESP" from anon;
