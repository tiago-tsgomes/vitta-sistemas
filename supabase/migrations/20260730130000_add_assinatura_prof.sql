-- Campo de imagem de assinatura do profissional, usada nos PDFs de receita/exame
ALTER TABLE public."PROFISSIONAL" ADD COLUMN IF NOT EXISTS "ASSINATURA_PROF" text;
