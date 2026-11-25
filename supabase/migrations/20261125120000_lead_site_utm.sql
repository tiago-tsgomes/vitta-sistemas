-- ============================================================
-- LEAD_SITE — de onde veio o lead (anúncio, campanha, palavra-chave)
-- Preenchidos pela landing page a partir dos parâmetros da URL:
--   utm_source / utm_medium / utm_campaign / utm_term / utm_content
--   gclid  (clique do Google Ads)  ·  fbclid (clique da Meta)
-- Rodar ANTES de publicar a nova versão de Site/lp.html.
-- ============================================================
ALTER TABLE public."LEAD_SITE"
  ADD COLUMN IF NOT EXISTS utm_source   text,
  ADD COLUMN IF NOT EXISTS utm_medium   text,
  ADD COLUMN IF NOT EXISTS utm_campaign text,
  ADD COLUMN IF NOT EXISTS utm_term     text,
  ADD COLUMN IF NOT EXISTS utm_content  text,
  ADD COLUMN IF NOT EXISTS gclid        text,
  ADD COLUMN IF NOT EXISTS fbclid       text;

-- O formulário é público: limita o tamanho para evitar abuso
ALTER TABLE public."LEAD_SITE" DROP CONSTRAINT IF EXISTS lead_site_utm_tamanho;
ALTER TABLE public."LEAD_SITE" ADD CONSTRAINT lead_site_utm_tamanho CHECK (
  coalesce(char_length(utm_source), 0)   <= 300 AND
  coalesce(char_length(utm_medium), 0)   <= 300 AND
  coalesce(char_length(utm_campaign), 0) <= 300 AND
  coalesce(char_length(utm_term), 0)     <= 300 AND
  coalesce(char_length(utm_content), 0)  <= 300 AND
  coalesce(char_length(gclid), 0)        <= 300 AND
  coalesce(char_length(fbclid), 0)       <= 300
);
