-- Comprovante de pagamento passa a ser um arquivo (PDF/imagem/etc) em vez de texto livre
ALTER TABLE public."PAGAMENTO"
  ADD COLUMN IF NOT EXISTS "COMPROVANTE_PATH"   text,
  ADD COLUMN IF NOT EXISTS "COMPROVANTE_NOME"   text,
  ADD COLUMN IF NOT EXISTS "COMPROVANTE_TIPO"   text,
  ADD COLUMN IF NOT EXISTS "COMPROVANTE_TAMANHO" bigint;

-- Bucket de storage para comprovantes de pagamento
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'comprovantes-pagamento',
  'comprovantes-pagamento',
  false,
  10485760,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- Políticas de storage (RLS em storage.objects)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'comprovante_pgto_storage_select'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "comprovante_pgto_storage_select" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'comprovantes-pagamento')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'comprovante_pgto_storage_insert'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "comprovante_pgto_storage_insert" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'comprovantes-pagamento')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'comprovante_pgto_storage_update'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "comprovante_pgto_storage_update" ON storage.objects
        FOR UPDATE TO authenticated
        USING (bucket_id = 'comprovantes-pagamento')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'comprovante_pgto_storage_delete'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "comprovante_pgto_storage_delete" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'comprovantes-pagamento')
    $pol$;
  END IF;
END $$;
