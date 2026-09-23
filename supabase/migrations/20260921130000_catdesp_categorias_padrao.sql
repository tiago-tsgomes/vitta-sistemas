-- Categorias de despesa padrão: toda empresa nasce com este conjunto e pode editar/excluir depois.
create or replace function public.seed_catdesp_padrao(p_id_emp uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public."CATDESP" ("ID_EMP", "NOME_CATDESP", "ICONE_CATDESP", "COR_CATDESP")
  values
    (p_id_emp, 'Aluguel',                    'home',     '#3B82F6'),
    (p_id_emp, 'Condomínio',                 'building', '#3B82F6'),
    (p_id_emp, 'Energia elétrica',           'zap',      '#F59E0B'),
    (p_id_emp, 'Água e esgoto',              'droplet',  '#2ABCD4'),
    (p_id_emp, 'Manutenção predial',         'wrench',   '#3B82F6'),
    (p_id_emp, 'Telefonia',                  'phone',    '#10B981'),
    (p_id_emp, 'Internet',                   'wifi',     '#10B981'),
    (p_id_emp, 'Software e assinaturas',     'card',     '#10B981'),
    (p_id_emp, 'Equipamentos de informática','laptop',   '#10B981'),
    (p_id_emp, 'Treinamentos e cursos',      'book',     '#127A8C'),
    (p_id_emp, 'Uniformes',                  'users',    '#127A8C'),
    (p_id_emp, 'Materiais de consumo',       'package',  '#F59E0B'),
    (p_id_emp, 'Material de limpeza',        'package',  '#F59E0B'),
    (p_id_emp, 'Contabilidade',              'file',     '#8B5CF6'),
    (p_id_emp, 'Assessoria jurídica',        'file',     '#8B5CF6'),
    (p_id_emp, 'Consultorias',               'users',    '#8B5CF6')
  on conflict do nothing;
$$;

revoke all on function public.seed_catdesp_padrao(uuid) from public, anon, authenticated;

create or replace function public.trg_empresa_seed_catdesp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.seed_catdesp_padrao(new."ID_EMP");
  return new;
end;
$$;

revoke all on function public.trg_empresa_seed_catdesp() from public, anon, authenticated;

create trigger trg_empresa_seed_catdesp
  after insert on public."EMPRESA"
  for each row execute function public.trg_empresa_seed_catdesp();

-- Empresas já existentes
select public.seed_catdesp_padrao("ID_EMP") from public."EMPRESA";
