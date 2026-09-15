-- Novos campos no formulário de Leads
alter table public."LEADS"
  add column "PROCURA_LEAD" text,
  add column "ABORDAGEM_LEAD" text,
  add column "ID_PROF" uuid references public."PROFISSIONAL"("ID_PROF"),
  add column "FOI_AGENDADO_LEAD" boolean,
  add column "ADERIU_BLOCO_LEAD" text,
  add column "OBSERVACAO_LEAD" text,
  add column "DESISTENCIA_LEAD" text;

-- Tabela de opções extensíveis para os campos de seleção do Lead
-- ID_EMP nulo = opção padrão do sistema (visível para todas as empresas)
-- ID_EMP preenchido = opção customizada cadastrada por uma empresa específica
create table public."LEAD_OPCAO" (
  "ID_OPCAO" uuid primary key default gen_random_uuid(),
  "ID_EMP" uuid references public."EMPRESA"("ID_EMP"),
  "CAMPO" text not null check ("CAMPO" in ('PROCURA','ABORDAGEM','ADERIU_BLOCO','DESISTENCIA')),
  "VALOR" text not null,
  "DTCRI_OPCAO" timestamptz not null default now()
);

alter table public."LEAD_OPCAO" enable row level security;

create policy "lead_opcao_select" on public."LEAD_OPCAO"
  for select
  using ("ID_EMP" is null or get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "lead_opcao_insert" on public."LEAD_OPCAO"
  for insert
  with check (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "lead_opcao_update" on public."LEAD_OPCAO"
  for update
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

create policy "lead_opcao_delete" on public."LEAD_OPCAO"
  for delete
  using (get_my_tipo_usu() = 'ADMIN_GLOBAL' or "ID_EMP" = get_my_empresa_id());

-- Seed das opções padrão (globais, ID_EMP nulo)
insert into public."LEAD_OPCAO" ("CAMPO","VALOR") values
  ('PROCURA','Psicólogo'),
  ('PROCURA','Psiquiatra'),
  ('PROCURA','Neuropsicólogo'),
  ('PROCURA','Profissional Específico'),
  ('PROCURA','Psicólogo Infantil'),
  ('PROCURA','Sem retorno'),
  ('ABORDAGEM','Procura Voluntária'),
  ('ABORDAGEM','Indicação Paciente'),
  ('ABORDAGEM','Encaminhado'),
  ('ABORDAGEM','Paciente Antigo'),
  ('ABORDAGEM','Outros'),
  ('ADERIU_BLOCO','Sim'),
  ('ADERIU_BLOCO','Não'),
  ('ADERIU_BLOCO','Consulta'),
  ('ADERIU_BLOCO','Indiferente'),
  ('ADERIU_BLOCO','Avaliativa'),
  ('DESISTENCIA','Sem Retorno'),
  ('DESISTENCIA','Sem Condições'),
  ('DESISTENCIA','Procura Convênio'),
  ('DESISTENCIA','Outros'),
  ('DESISTENCIA','Agendou e Desmarcou');
