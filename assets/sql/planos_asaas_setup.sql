-- ============================================================
-- Planos + Asaas — Ajuste do schema existente
-- A tabela PLANO e a tabela EMPRESA já existem.
-- Este script APENAS adiciona colunas faltantes e insere
-- os 4 planos padrão caso ainda não existam.
-- Execute no: Supabase Dashboard > SQL Editor
-- https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. Adicionar colunas faltantes em PLANO
-- ------------------------------------------------------------
ALTER TABLE "PLANO"
  ADD COLUMN IF NOT EXISTS "PRECO_PLANO"          NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS "MAX_USUARIOS_PLANO"   INT,           -- NULL = ilimitado
  ADD COLUMN IF NOT EXISTS "TEM_APP_PLANO"        BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS "TEM_IA_PLANO"         BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS "PERFIL_HIBRIDO_PLANO" BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS "ASAAS_PLAN_ID"        TEXT;

-- ------------------------------------------------------------
-- 2. Inserir os 4 planos padrão (somente se não existirem)
-- ------------------------------------------------------------
INSERT INTO "PLANO" ("NOME_PLANO", "PRECO_PLANO", "MAX_USUARIOS_PLANO", "TEM_APP_PLANO", "TEM_IA_PLANO", "PERFIL_HIBRIDO_PLANO", "ATIVO_PLANO", "DTCRI_PLANO")
SELECT 'Solo', 97.00, 2, true, true, true, true, NOW()
WHERE NOT EXISTS (SELECT 1 FROM "PLANO" WHERE "NOME_PLANO" = 'Solo');

INSERT INTO "PLANO" ("NOME_PLANO", "PRECO_PLANO", "MAX_USUARIOS_PLANO", "TEM_APP_PLANO", "TEM_IA_PLANO", "PERFIL_HIBRIDO_PLANO", "ATIVO_PLANO", "DTCRI_PLANO")
SELECT 'Essencial', 147.00, NULL, false, false, false, true, NOW()
WHERE NOT EXISTS (SELECT 1 FROM "PLANO" WHERE "NOME_PLANO" = 'Essencial');

INSERT INTO "PLANO" ("NOME_PLANO", "PRECO_PLANO", "MAX_USUARIOS_PLANO", "TEM_APP_PLANO", "TEM_IA_PLANO", "PERFIL_HIBRIDO_PLANO", "ATIVO_PLANO", "DTCRI_PLANO")
SELECT 'Clínica', 197.00, NULL, true, false, false, true, NOW()
WHERE NOT EXISTS (SELECT 1 FROM "PLANO" WHERE "NOME_PLANO" = 'Clínica');

INSERT INTO "PLANO" ("NOME_PLANO", "PRECO_PLANO", "MAX_USUARIOS_PLANO", "TEM_APP_PLANO", "TEM_IA_PLANO", "PERFIL_HIBRIDO_PLANO", "ATIVO_PLANO", "DTCRI_PLANO")
SELECT 'Pro', 297.00, NULL, true, true, false, true, NOW()
WHERE NOT EXISTS (SELECT 1 FROM "PLANO" WHERE "NOME_PLANO" = 'Pro');

-- ------------------------------------------------------------
-- 3. Adicionar colunas faltantes em EMPRESA
--    (ID_PLANO já existe como FK — não incluído aqui)
-- ------------------------------------------------------------
ALTER TABLE "EMPRESA"
  ADD COLUMN IF NOT EXISTS "STATUS_EMP"            TEXT DEFAULT 'trial',
  ADD COLUMN IF NOT EXISTS "TRIAL_EXPIRA_EM"       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "ACESSO_ATE"            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "ASAAS_CUSTOMER_ID"     TEXT,
  ADD COLUMN IF NOT EXISTS "ASAAS_SUBSCRIPTION_ID" TEXT;
