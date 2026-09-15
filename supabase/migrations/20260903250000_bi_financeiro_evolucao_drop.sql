-- Desfaz a categoria 2 (Comparação temporal / crescimento / evolução) do
-- Financeiro do Vitta BI, a pedido do usuário em 03/09/2026 ("vamos voltar
-- depois nele"). A feature passou por 3 redesenhos no mesmo dia e foi
-- abandonada antes de qualquer versão ser confirmada como aplicada no banco.
--
-- Este migration remove bi_financeiro_evolucao em TODAS as assinaturas que
-- ela já teve neste dia, para deixar o banco limpo independente de qual
-- versão (se alguma) o usuário chegou a rodar no SQL Editor:
--   - bi_financeiro_evolucao(uuid, uuid)         -- versão original, fixa 6 meses
--   - bi_financeiro_evolucao(uuid, text, uuid)   -- versão orientada a período

drop function if exists public.bi_financeiro_evolucao(uuid, uuid);
drop function if exists public.bi_financeiro_evolucao(uuid, text, uuid);
