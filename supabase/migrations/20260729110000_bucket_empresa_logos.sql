-- Bucket de storage para a logo da empresa (usada no header do app e no PDF de exames)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'empresa-logos',
  'empresa-logos',
  true,
  2097152,
  ARRAY['image/png','image/jpeg','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Políticas de storage (RLS na tabela storage.objects)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'empresa_logo_public_select'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "empresa_logo_public_select" ON storage.objects
        FOR SELECT TO public
        USING (bucket_id = 'empresa-logos')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'empresa_logo_insert'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "empresa_logo_insert" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'empresa-logos')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'empresa_logo_update'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "empresa_logo_update" ON storage.objects
        FOR UPDATE TO authenticated
        USING (bucket_id = 'empresa-logos')
        WITH CHECK (bucket_id = 'empresa-logos')
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'empresa_logo_delete'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "empresa_logo_delete" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'empresa-logos')
    $pol$;
  END IF;
END $$;
