-- Notificações (sino): quem pode criar
--  + inclui o AUTONOMO (dono do plano Solo), que antes ficava de fora
--  + só cria notificação na própria empresa (antes não conferia a empresa:
--    qualquer usuário conseguia criar avisos no sino de outra clínica)
DROP POLICY IF EXISTS "notif_insert" ON public."NOTIFICACAO";
CREATE POLICY "notif_insert" ON public."NOTIFICACAO"
  FOR INSERT TO authenticated
  WITH CHECK (
    get_my_tipo_usu() = 'ADMIN_GLOBAL'
    OR (
      get_my_tipo_usu() = ANY (ARRAY['ADMIN_EMPRESA', 'SECRETARIA', 'PROFISSIONAL', 'AUTONOMO'])
      AND "ID_EMP" = get_my_empresa_id()
    )
  );
