-- ─────────────────────────────────────────────────────────────
-- Corrige fn_set_dtalter(): o trigger trg_dtalter_usuario (BEFORE
-- UPDATE em USUARIO) chama hstore(), que vive no schema
-- "extensions". A função não tinha SEARCH_PATH próprio, então
-- herdava o search_path de quem disparou o UPDATE. RPCs SECURITY
-- DEFINER que fazem "SET search_path = public" (sem "extensions"),
-- como set_ultimo_acesso_empresa, faziam o trigger falhar com
-- "function hstore(text, text) does not exist" e o UPDATE inteiro
-- era revertido — silenciosamente, pois o client (index.html)
-- engole o erro em try{}catch(_){}. Resultado: ULTIMO_ACESSO_EMP
-- nunca era gravado e a tela de Log sempre mostrava "Nunca acessou".
--
-- Corrigido em 24/07/2026: fn_set_dtalter agora define seu próprio
-- SEARCH_PATH (public, extensions), então funciona independente do
-- search_path de quem chamou o UPDATE.
--
-- Execute este SQL no Supabase Dashboard > SQL Editor.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_set_dtalter()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $function$
DECLARE
    col_name TEXT;
BEGIN
    col_name := TG_ARGV[0];
    NEW := NEW #= hstore(col_name, NOW()::TEXT);
    RETURN NEW;
END;
$function$;
