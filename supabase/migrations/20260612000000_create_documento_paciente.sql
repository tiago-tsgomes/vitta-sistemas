-- Tabela de documentos do paciente
CREATE TABLE IF NOT EXISTS public."DOCUMENTO_PACIENTE" (
  "ID_DOC"         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "PAC_ID"         uuid NOT NULL REFERENCES public."PACIENTE"("ID_PAC") ON DELETE CASCADE,
  "EMP_ID"         uuid REFERENCES public."EMPRESA"("ID_EMP") ON DELETE SET NULL,
  "PROF_ID"        uuid REFERENCES public."PROFISSIONAL"("ID_PROF") ON DELETE SET NULL,
  "NOME_ARQUIVO"   text NOT NULL,
  "TIPO_ARQUIVO"   text,
  "CATEGORIA"      text CHECK ("CATEGORIA" IN ('Relatório','Declaração','Receita','Ficha','Avaliação')),
  "DESCRICAO"      text,
  "STORAGE_PATH"   text NOT NULL,
  "TAMANHO_BYTES"  bigint,
  "CRIADO_EM"      timestamptz NOT NULL DEFAULT now(),
  "CRIADO_POR"     uuid
);

CREATE INDEX IF NOT EXISTS idx_doc_pac  ON public."DOCUMENTO_PACIENTE"("PAC_ID");
CREATE INDEX IF NOT EXISTS idx_doc_prof ON public."DOCUMENTO_PACIENTE"("PROF_ID");
CREATE INDEX IF NOT EXISTS idx_doc_emp  ON public."DOCUMENTO_PACIENTE"("EMP_ID");

ALTER TABLE public."DOCUMENTO_PACIENTE" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "doc_select" ON public."DOCUMENTO_PACIENTE"
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "doc_insert" ON public."DOCUMENTO_PACIENTE"
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "doc_delete" ON public."DOCUMENTO_PACIENTE"
  FOR DELETE TO authenticated USING (true);

-- Bucket de storage para documentos dos pacientes
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documentos-paciente',
  'documentos-paciente',
  false,
  10485760,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/gif',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- Políticas de storage (RLS na tabela storage.objects)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'doc_storage_select'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "doc_storage_select" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'documentos-paciente')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'doc_storage_insert'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "doc_storage_insert" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'documentos-paciente')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'doc_storage_delete'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "doc_storage_delete" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'documentos-paciente')
    $pol$;
  END IF;
END $$;
