-- 003_validate_assigned_data. Depende de 001, 002 y asignaciones revisadas.
-- No asigna ni elimina datos. ABORTA si queda cualquier fila en cuarentena.
-- Al finalizar impone NOT NULL a tenant_id y valida relaciones/procedencia.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$
DECLARE t text; n bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM directa_private.migration_log WHERE migration_id='002_reviewed_legacy_assignment') THEN
   RAISE EXCEPTION 'Primero aplicar 002 y completar las asignaciones revisadas';
 END IF;
 IF EXISTS(SELECT 1 FROM directa_private.migration_log WHERE migration_id='003_validate_assigned_data') THEN
   RAISE EXCEPTION '003 ya fue aplicada';
 END IF;
 FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono'] LOOP
   EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id IS NULL',t) INTO n;
   IF n>0 THEN RAISE EXCEPTION '% tiene % filas sin organización. No se asignan automáticamente',t,n; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.usuarios WHERE auth_user_id IS NULL) THEN
   RAISE EXCEPTION 'Existen perfiles sin identidad de Supabase Auth';
 END IF;
 FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono'] LOOP
   EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I',t,'directa_'||t||'_tenant_required');
   EXECUTE format('ALTER TABLE public.%I ALTER COLUMN tenant_id SET NOT NULL',t);
 END LOOP;
END $guard$;
ALTER TABLE public.usuarios ALTER COLUMN auth_user_id SET NOT NULL;
ALTER TABLE public.document_chunks VALIDATE CONSTRAINT directa_chunks_document_tenant_fk;
ALTER TABLE public.analisis VALIDATE CONSTRAINT directa_analisis_document_tenant_fk;
ALTER TABLE public.valoraciones VALIDATE CONSTRAINT directa_valoraciones_document_tenant_fk;
ALTER TABLE public.document_chunks VALIDATE CONSTRAINT directa_chunks_model_required;
INSERT INTO directa_private.migration_log(migration_id,source_commit)
 VALUES('003_validate_assigned_data','2f3f3d5dbda14ff6580cc6024b89358d3e1c186d');
COMMIT;
SELECT migration_id,applied_at FROM directa_private.migration_log ORDER BY applied_at;
