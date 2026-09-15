-- Flag de receita de controle especial (gera PDF em 2 vias com campos de identificação da farmácia)
ALTER TABLE public."CONSULTA_DOCUMENTO" ADD COLUMN IF NOT EXISTS "ESPECIAL_DOC_CONS" boolean NOT NULL DEFAULT false;
