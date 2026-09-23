-- Despesa paga não pode ser excluída (nem pelo ADMIN_GLOBAL). Para excluir, é preciso desfazer o pagamento antes.
drop policy "despesa_delete" on public."DESPESA";

create policy "despesa_delete" on public."DESPESA"
  for delete
  using (
    "DTPAG_DESP" is null
    and (
      get_my_tipo_usu() = 'ADMIN_GLOBAL'
      or (get_my_tipo_usu() in ('ADMIN_EMPRESA', 'SECRETARIA') and "ID_EMP" = get_my_empresa_id())
    )
  );
