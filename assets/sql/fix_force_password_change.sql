-- Corrige a função set_force_password_change para usar merge (||) correto
-- Execute este SQL no Supabase Dashboard > SQL Editor

CREATE OR REPLACE FUNCTION public.set_force_password_change(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE auth.users
  SET raw_user_meta_data = raw_user_meta_data || '{"force_password_change": true}'::jsonb
  WHERE email = lower(trim(p_email));
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_force_password_change(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_force_password_change(text) TO anon;
