alter table public."EMPRESA"
  add column "BI_ACESSO_EMP" boolean not null default false;

comment on column public."EMPRESA"."BI_ACESSO_EMP" is
  'Libera o menu Vitta BI para o perfil Administrador (ADMIN_EMPRESA) da empresa. Controlado manualmente pelo Admin Global no cadastro da empresa.';
