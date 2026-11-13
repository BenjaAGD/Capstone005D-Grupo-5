-- 002_reviewed_legacy_assignment
-- Depende de 001. Solo crea herramientas administrativas para asignaciones
-- revisadas. NO asigna automáticamente ninguna fila, organización o usuario.
-- Las llamadas con IDs reales se prepararán después de revisar el inventario.
-- Ejecución: SQL Editor como administrador. No exponer directa_private por API.
-- Mantener detenido el backend antiguo; ninguna cuenta app ejecuta estas funciones.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM directa_private.migration_log WHERE migration_id='001_identity_tenants_rls_vector') THEN
   RAISE EXCEPTION 'Ejecutar y validar 001 antes de 002';
 END IF;
 IF EXISTS(SELECT 1 FROM directa_private.migration_log WHERE migration_id='002_reviewed_legacy_assignment') THEN
   RAISE EXCEPTION '002 ya fue aplicada';
 END IF;
END $guard$;

CREATE FUNCTION directa_private.record_review(p_tenant uuid,p_action text,p_resource text,p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
BEGIN
 IF length(btrim(COALESCE(p_reason,''))) NOT BETWEEN 12 AND 500 THEN
   RAISE EXCEPTION 'Registrar un motivo de revisión entre 12 y 500 caracteres';
 END IF;
 INSERT INTO directa_private.security_audit(tenant_id,actor_id,database_actor,action,resource_id,reason)
 VALUES(p_tenant,auth.uid(),current_user,p_action,p_resource,p_reason);
END $fn$;

CREATE FUNCTION directa_private.register_organization(p_name text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE result uuid;
BEGIN
 INSERT INTO public.organizations(name) VALUES(p_name) RETURNING id INTO result;
 PERFORM directa_private.record_review(result,'organization.created',result::text,p_reason);
 RETURN result;
END $fn$;

CREATE FUNCTION directa_private.register_member(p_tenant uuid,p_auth_user uuid,p_role text,p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
BEGIN
 -- auth.users debe existir por un alta real en Supabase Auth. No se crean
 -- contraseñas, usuarios ficticios ni bypass de MFA en esta migración.
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user) THEN
   RAISE EXCEPTION 'El UUID debe pertenecer a un usuario real de Supabase Auth';
 END IF;
 INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(p_tenant,p_auth_user,p_role);
 PERFORM directa_private.record_review(p_tenant,'membership.created',p_auth_user::text,p_reason);
END $fn$;

CREATE FUNCTION directa_private.assign_legacy_document(
 p_document_id text,p_tenant uuid,p_known_creator uuid,p_confirmed_model text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE doc public.documentos; chunks_n integer; analyses_n integer; ratings_n integer;
BEGIN
 SELECT * INTO doc FROM public.documentos WHERE id=p_document_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Documento no encontrado'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_tenant AND active) THEN
   RAISE EXCEPTION 'La organización debe existir y estar activa';
 END IF;
 IF doc.tenant_id IS NOT NULL AND doc.tenant_id<>p_tenant THEN
   RAISE EXCEPTION 'El documento ya pertenece a otra empresa';
 END IF;
 IF doc.created_by IS NOT NULL AND p_known_creator IS DISTINCT FROM doc.created_by THEN
   RAISE EXCEPTION 'No sobrescribir un autor previamente identificado';
 END IF;
 IF p_known_creator IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.memberships WHERE tenant_id=p_tenant AND user_id=p_known_creator) THEN
   RAISE EXCEPTION 'El autor conocido debe tener membresía en la organización';
 END IF;
 IF EXISTS(SELECT 1 FROM public.document_chunks WHERE document_id=p_document_id AND embedding IS NOT NULL)
    AND p_confirmed_model IS DISTINCT FROM 'nvidia/nemotron-3-embed-1b' THEN
   RAISE EXCEPTION 'Confirmar con evidencia el modelo histórico antes de habilitar sus embeddings';
 END IF;
 IF EXISTS(SELECT 1 FROM public.document_chunks WHERE document_id=p_document_id AND tenant_id<>p_tenant)
 OR EXISTS(SELECT 1 FROM public.analisis WHERE document_id=p_document_id AND tenant_id<>p_tenant)
 OR EXISTS(SELECT 1 FROM public.valoraciones WHERE document_id=p_document_id AND tenant_id<>p_tenant) THEN
   RAISE EXCEPTION 'Se detectó una relación cruzada; revisar sin modificar datos';
 END IF;
 UPDATE public.documentos SET tenant_id=p_tenant,created_by=p_known_creator WHERE id=p_document_id;
 UPDATE public.document_chunks SET tenant_id=p_tenant,
   embedding_model=CASE WHEN embedding IS NOT NULL THEN p_confirmed_model ELSE embedding_model END
 WHERE document_id=p_document_id;
 GET DIAGNOSTICS chunks_n=ROW_COUNT;
 UPDATE public.analisis SET tenant_id=p_tenant WHERE document_id=p_document_id;
 GET DIAGNOSTICS analyses_n=ROW_COUNT;
 -- Autoría de valoraciones se revisa aparte; no se inventa que el autor del
 -- documento haya hecho también cada pregunta o valoración.
 UPDATE public.valoraciones SET tenant_id=p_tenant WHERE document_id=p_document_id;
 GET DIAGNOSTICS ratings_n=ROW_COUNT;
 PERFORM directa_private.record_review(p_tenant,'document.assigned',p_document_id,p_reason);
 RETURN jsonb_build_object('document_id',p_document_id,'chunks',chunks_n,'analyses',analyses_n,'ratings',ratings_n);
END $fn$;

CREATE FUNCTION directa_private.assign_legacy_record(
 p_table text,p_record_id uuid,p_tenant uuid,p_known_user uuid,p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE row_data jsonb; ref text; item jsonb; existing_tenant uuid;
BEGIN
 IF p_table NOT IN ('usuarios','valoraciones','lecciones','perfiles_tono') THEN
   RAISE EXCEPTION 'Tabla no permitida para asignación individual';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_tenant AND active) THEN
   RAISE EXCEPTION 'La organización debe existir y estar activa';
 END IF;
 EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE id=$1 FOR UPDATE',p_table)
   INTO row_data USING p_record_id;
 IF row_data IS NULL THEN RAISE EXCEPTION 'Registro no encontrado'; END IF;
 existing_tenant=(row_data->>'tenant_id')::uuid;
 IF existing_tenant IS NOT NULL AND existing_tenant<>p_tenant THEN
   RAISE EXCEPTION 'No transferir registros entre empresas';
 END IF;
 IF p_known_user IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.memberships WHERE tenant_id=p_tenant AND user_id=p_known_user) THEN
   RAISE EXCEPTION 'La identidad conocida debe tener membresía en esta empresa';
 END IF;
 IF p_table='usuarios' AND p_known_user IS NULL THEN
   RAISE EXCEPTION 'Un perfil usuarios requiere su UUID de Supabase Auth verificado';
 END IF;
 IF p_table='valoraciones' AND row_data->>'document_id' IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.documentos WHERE id=row_data->>'document_id' AND tenant_id=p_tenant) THEN
   RAISE EXCEPTION 'Asignar primero el documento y comprobar su organización';
 END IF;
 IF p_table='lecciones' THEN
   FOR ref IN SELECT jsonb_array_elements_text(row_data->'origen') LOOP
     IF NOT EXISTS(SELECT 1 FROM public.valoraciones WHERE id::text=ref AND tenant_id=p_tenant) THEN
       RAISE EXCEPTION 'El origen de la lección no está asignado a esta empresa';
     END IF;
   END LOOP;
 END IF;
 IF p_table='perfiles_tono' THEN
   FOR item IN SELECT jsonb_array_elements(row_data->'corpus') LOOP
     IF item->>'document_id' IS NULL OR NOT EXISTS(
       SELECT 1 FROM public.documentos WHERE id=item->>'document_id' AND tenant_id=p_tenant) THEN
       RAISE EXCEPTION 'El corpus del perfil incluye un documento sin pertenencia comprobada';
     END IF;
   END LOOP;
 END IF;
 IF p_table='usuarios' THEN
   IF row_data->>'auth_user_id' IS NOT NULL AND (row_data->>'auth_user_id')::uuid IS DISTINCT FROM p_known_user THEN
     RAISE EXCEPTION 'No sobrescribir una identidad previamente asignada';
   END IF;
   UPDATE public.usuarios SET tenant_id=p_tenant,auth_user_id=p_known_user WHERE id=p_record_id;
 ELSE
   IF row_data->>'created_by' IS NOT NULL AND (row_data->>'created_by')::uuid IS DISTINCT FROM p_known_user THEN
     RAISE EXCEPTION 'No sobrescribir una autoría previamente identificada';
   END IF;
   EXECUTE format('UPDATE public.%I SET tenant_id=$1,created_by=$2 WHERE id=$3',p_table)
     USING p_tenant,p_known_user,p_record_id;
 END IF;
 PERFORM directa_private.record_review(p_tenant,p_table||'.assigned',p_record_id::text,p_reason);
END $fn$;

-- Ninguna función administrativa es ejecutable por roles de aplicación,
-- incluido service_role. Solo queda el booleano utilizado por las políticas.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA directa_private FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION directa_private.can_access_tenant(uuid,text) TO authenticated;
INSERT INTO directa_private.migration_log(migration_id,source_commit)
 VALUES('002_reviewed_legacy_assignment','2f3f3d5dbda14ff6580cc6024b89358d3e1c186d');
COMMIT;
SELECT migration_id,applied_at FROM directa_private.migration_log ORDER BY applied_at;
