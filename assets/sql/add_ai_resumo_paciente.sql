-- Migração: adiciona colunas de resumo IA na tabela PACIENTE
-- Execute este script no Supabase SQL Editor

ALTER TABLE "PACIENTE"
  ADD COLUMN IF NOT EXISTS "AI_RESUMO_PAC"    TEXT,
  ADD COLUMN IF NOT EXISTS "AI_RESUMO_DT_PAC" TIMESTAMPTZ;

COMMENT ON COLUMN "PACIENTE"."AI_RESUMO_PAC"    IS 'HTML do resumo clínico gerado por IA';
COMMENT ON COLUMN "PACIENTE"."AI_RESUMO_DT_PAC" IS 'Data/hora em que o resumo foi gerado';
