-- ============================================================
-- VITTA SISTEMAS — Migração: tabela AI_CONFIG
-- Execute este SQL no Supabase Dashboard → SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS public."AI_CONFIG" (
  "CHAVE"    text        PRIMARY KEY,
  "VALOR"    text,
  "TITULO"   text        NOT NULL,
  "DESCRICAO" text,
  "TIPO"     text        NOT NULL DEFAULT 'PROMPT',
  "DTCRI"    timestamptz NOT NULL DEFAULT now(),
  "DTUPD"    timestamptz NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE public."AI_CONFIG" ENABLE ROW LEVEL SECURITY;

-- ADMIN_GLOBAL: acesso total
CREATE POLICY "ai_config_admin_global" ON public."AI_CONFIG"
  FOR ALL TO authenticated
  USING  ((auth.jwt()->'user_metadata'->>'tipo_usu') = 'ADMIN_GLOBAL')
  WITH CHECK ((auth.jwt()->'user_metadata'->>'tipo_usu') = 'ADMIN_GLOBAL');

-- Profissional / Admin Empresa: leitura (para buscar chave e prompt ao usar IA)
CREATE POLICY "ai_config_profissional_read" ON public."AI_CONFIG"
  FOR SELECT TO authenticated
  USING ((auth.jwt()->'user_metadata'->>'tipo_usu') IN ('PROFISSIONAL', 'ADMIN_EMPRESA'));

-- Dados padrão
INSERT INTO public."AI_CONFIG" ("CHAVE", "TITULO", "DESCRICAO", "TIPO", "VALOR") VALUES
(
  'AI_PROVIDER',
  'Provedor de IA Ativo',
  'Provedor de IA atualmente selecionado (CLAUDE, OPENAI, GEMINI ou META)',
  'CONFIG',
  'CLAUDE'
),
(
  'AI_MODEL',
  'Modelo de IA Ativo',
  'Modelo de IA atualmente selecionado',
  'CONFIG',
  'claude-haiku-4-5-20251001'
),
(
  'CLAUDE_API_KEY',
  'Chave da API Claude',
  'Chave de API do Claude (Anthropic). Obtenha em console.anthropic.com → API Keys.',
  'APIKEY',
  NULL
),
(
  'PROMPT_RESUMO_HISTORICO',
  'Resumo do Histórico Clínico',
  'Prompt usado ao clicar em "Resumo IA" durante uma consulta ou no prontuário mobile. Analisa todo o histórico do paciente.',
  'PROMPT',
  E'Você é um assistente clínico especializado. Analise o histórico clínico completo do paciente abaixo e gere um resumo estruturado e objetivo para o profissional de saúde que está iniciando o atendimento. Use linguagem técnica e seja conciso. Responda sempre em português brasileiro.\n\nFormate sua resposta com exatamente estas 4 seções (inclua os emojis e os títulos como mostrado):\n\n📋 EVOLUÇÃO CLÍNICA\nDescreva de forma objetiva a evolução do paciente: diagnósticos, frequência de atendimentos, tendência geral (melhora, piora, estável). Mencione as consultas mais recentes.\n\n💊 MEDICAMENTOS E PRESCRIÇÕES\nListe os medicamentos prescritos nas consultas anteriores com doses e frequência quando disponíveis. Se não houver prescrições, informe.\n\n📊 SINAIS VITAIS — TENDÊNCIA\nAnalise a evolução dos sinais vitais registrados (peso, PA, FC, SpO₂, IMC). Destaque tendências importantes. Se não houver dados, informe.\n\n⚠️ PONTOS DE ATENÇÃO\nListe de 2 a 5 pontos importantes que o profissional deve observar ou investigar nesta consulta, com base no histórico. Inclua padrões recorrentes, medicamentos aguardando reavaliação e queixas repetidas.\n\nSeja objetivo. Não invente informações que não estejam nos dados fornecidos. Se alguma seção não tiver dados suficientes, escreva "Sem dados registrados".'
),
(
  'OPENAI_API_KEY',
  'Chave da API OpenAI',
  'Chave para modelos GPT da OpenAI. Obtenha em platform.openai.com → API Keys.',
  'APIKEY',
  NULL
),
(
  'GEMINI_API_KEY',
  'Chave da API Google Gemini',
  'Chave para modelos Gemini do Google. Obtenha em aistudio.google.com → Get API Key.',
  'APIKEY',
  NULL
),
(
  'META_API_KEY',
  'Chave da API Groq (Meta Llama)',
  'Chave Groq para modelos Llama da Meta. Obtenha em console.groq.com → API Keys (gratuito).',
  'APIKEY',
  NULL
)
ON CONFLICT ("CHAVE") DO NOTHING;
