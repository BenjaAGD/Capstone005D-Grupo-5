-- DIRECTA V4 / 001_identity_tenants_rls_vector
-- Incremental, transaccional y SIN BORRADO de filas, tablas, texto o embeddings.
-- Requiere revisión del inventario 000, respaldo y ventana de mantenimiento.
-- CAMBIO DE ACCESO: el cliente antiguo perderá acceso; registros históricos sin
-- tenant/procedencia quedan en cuarentena hasta una asignación revisada (002).
-- Detener el backend antiguo y sus workers: una service_role OMITE RLS y su
-- endpoint anónimo continuaría siendo peligroso. No reabrirlo antes del nuevo JWT.
-- No ejecutar desde la app, Flutter, PostgREST ni con service_role.
-- Solo ejecutar personalmente en el SQL Editor, tras revisar 000.
-- Mantiene vector(2048), halfvec(2048), HNSW y firma pública de la RPC.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';

DO $preflight$
DECLARE t text; vector_schema text; dim integer; arg_count integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Ejecutar con el administrador del SQL Editor, no con un rol de aplicación';
  END IF;
  IF to_regnamespace('directa_private') IS NOT NULL THEN
    RAISE EXCEPTION 'directa_private ya existe. No repetir 001 ni mezclar migraciones';
  END IF;
  IF to_regclass('public.organizations') IS NOT NULL OR to_regclass('public.memberships') IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe un modelo organizations/memberships: revisar antes de migrar';
  END IF;
  IF to_regclass('auth.users') IS NULL OR to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('auth.jwt()') IS NULL THEN
    RAISE EXCEPTION 'Falta el esquema de Supabase Auth esperado';
  END IF;
  FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono'] LOOP
    IF to_regclass('public.'||t) IS NULL THEN RAISE EXCEPTION 'Falta tabla public.%',t; END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
      AND table_name=t AND column_name='tenant_id') THEN
      RAISE EXCEPTION 'public.% ya tiene tenant_id: se requiere reconciliar el esquema',t;
    END IF;
  END LOOP;
  SELECT n.nspname INTO vector_schema FROM pg_extension e
  JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='vector';
  IF vector_schema IS NULL THEN RAISE EXCEPTION 'pgvector debe existir; no se cambia de motor'; END IF;
  SELECT a.atttypmod INTO dim FROM pg_attribute a
    WHERE a.attrelid='public.document_chunks'::regclass AND a.attname='embedding'
    AND a.atttypid=(quote_ident(vector_schema)||'.vector')::regtype;
  IF dim IS DISTINCT FROM 2048 THEN RAISE EXCEPTION 'Se esperaba vector(2048); no se modifica la dimensión'; END IF;
  IF to_regtype(quote_ident(vector_schema)||'.halfvec') IS NULL THEN
    RAISE EXCEPTION 'La versión de pgvector debe soportar halfvec para el índice existente';
  END IF;
  SELECT count(*) INTO arg_count FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='match_document_chunks';
  IF arg_count<>1 THEN RAISE EXCEPTION 'Se esperaba una RPC match_document_chunks; revisar sobrecargas'; END IF;
  IF to_regprocedure(format('public.match_document_chunks(%I.vector,double precision,integer,text)',vector_schema)) IS NULL THEN
    RAISE EXCEPTION 'La firma de la RPC difiere del código auditado; revisar antes de crear una sobrecarga';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND p.proname<>'match_document_chunks'
    AND NOT EXISTS(SELECT 1 FROM pg_depend dep WHERE dep.classid='pg_proc'::regclass
      AND dep.objid=p.oid AND dep.deptype='e')) THEN
    RAISE EXCEPTION 'Hay funciones SECURITY DEFINER adicionales en public; revisar permisos antes de aplicar 001';
  END IF;
  IF EXISTS(
    SELECT 1 FROM pg_depend dep JOIN pg_rewrite rw ON rw.oid=dep.objid
    JOIN pg_class v ON v.oid=rw.ev_class JOIN pg_class source ON source.oid=dep.refobjid
    JOIN pg_namespace ns ON ns.oid=source.relnamespace
    WHERE v.relkind IN ('v','m') AND ns.nspname='public' AND source.relname IN
      ('usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono')) THEN
    RAISE EXCEPTION 'Hay vistas dependientes: revisar seguridad e inventario antes de aplicar 001';
  END IF;
END $preflight$;

-- Estabilizar el inventario dentro de la transacción. Debe estar detenida la
-- aplicación: este bloqueo dura hasta COMMIT y aborta tras 5 s si hay actividad.
LOCK TABLE public.usuarios,public.documentos,public.document_chunks,public.analisis,
 public.valoraciones,public.lecciones,public.perfiles_tono IN ACCESS EXCLUSIVE MODE;

-- Las identidades históricas no se convierten silenciosamente en auth.users.
CREATE SCHEMA directa_private;
REVOKE ALL ON SCHEMA directa_private FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA directa_private TO authenticated;
REVOKE CREATE ON SCHEMA public FROM PUBLIC,anon,authenticated;

CREATE TABLE directa_private.migration_log(
  migration_id text PRIMARY KEY,source_commit text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE directa_private.policy_archive(
  archived_at timestamptz NOT NULL DEFAULT now(),table_name text NOT NULL,policy jsonb NOT NULL);
CREATE TABLE directa_private.baseline_counts(table_name text PRIMARY KEY,rows_before bigint NOT NULL);
CREATE TABLE directa_private.security_audit(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id uuid,actor_id uuid,
  database_actor text NOT NULL,action text NOT NULL,resource_id text,
  reason text,recorded_at timestamptz NOT NULL DEFAULT now());
REVOKE ALL ON ALL TABLES IN SCHEMA directa_private FROM PUBLIC,anon,authenticated,service_role;

DO $snapshot$
DECLARE t text; n bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono'] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I',t) INTO n;
    INSERT INTO directa_private.baseline_counts VALUES(t,n);
  END LOOP;
END $snapshot$;
INSERT INTO directa_private.policy_archive(table_name,policy)
SELECT tablename,to_jsonb(p) FROM pg_policies p WHERE schemaname='public'
AND tablename IN ('usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono');

CREATE TABLE public.organizations(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 160),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.memberships(
  tenant_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role text NOT NULL CHECK(role IN ('owner','admin','gerente_general','secretaria','director')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(tenant_id,user_id));
CREATE INDEX memberships_user_active ON public.memberships(user_id,tenant_id) WHERE active;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

-- Única lectura elevada necesaria para evitar recursión de RLS de membresías.
-- Sin SQL dinámico, search_path vacío, sin devolver filas ni aceptar user_id.
CREATE FUNCTION directa_private.can_access_tenant(p_tenant uuid,p_permission text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
  SELECT auth.uid() IS NOT NULL AND EXISTS(
    SELECT 1 FROM public.memberships m JOIN public.organizations o ON o.id=m.tenant_id
    WHERE m.user_id=auth.uid() AND m.tenant_id=p_tenant AND m.active AND o.active
    AND (m.role='director' OR COALESCE(auth.jwt()->>'aal','')='aal2')
    AND CASE
      WHEN p_permission IN ('documents.read','analysis.read','learning.read') THEN true
      WHEN p_permission='documents.write' THEN m.role IN ('owner','admin','gerente_general','secretaria')
      WHEN p_permission IN ('documents.delete','learning.manage') THEN m.role IN ('owner','admin','gerente_general')
      WHEN p_permission='members.read' THEN m.role IN ('owner','admin')
      ELSE false END);
$fn$;
REVOKE ALL ON FUNCTION directa_private.can_access_tenant(uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION directa_private.can_access_tenant(uuid,text) TO authenticated;

DO $columns$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN tenant_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT',t);
    -- NOT VALID conserva filas previas sin inventar su empresa, pero exige tenant
    -- para nuevas filas o modificaciones. La validación final es el paso 003.
    EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I CHECK(tenant_id IS NOT NULL) NOT VALID',t,'directa_'||t||'_tenant_required');
    EXECUTE format('CREATE INDEX %I ON public.%I(tenant_id)', 'directa_'||t||'_tenant_idx',t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['documentos','valoraciones','lecciones','perfiles_tono'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN created_by uuid',t);
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN created_by SET DEFAULT auth.uid()',t);
    EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY(tenant_id,created_by) REFERENCES public.memberships(tenant_id,user_id)',t,'directa_'||t||'_creator_fk');
  END LOOP;
END $columns$;
ALTER TABLE public.usuarios ADD COLUMN auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX directa_usuarios_auth_unique ON public.usuarios(tenant_id,auth_user_id) WHERE auth_user_id IS NOT NULL;
ALTER TABLE public.usuarios ADD CONSTRAINT directa_usuarios_member_fk
 FOREIGN KEY(tenant_id,auth_user_id) REFERENCES public.memberships(tenant_id,user_id);
ALTER TABLE public.documentos ADD CONSTRAINT directa_documento_tenant_unique UNIQUE(id,tenant_id);
-- Se mantienen las claves originales. Esta relación adicional impide enlazar
-- un fragmento o resultado de A con un documento de B, también para un worker.
ALTER TABLE public.document_chunks ADD CONSTRAINT directa_chunks_document_tenant_fk
 FOREIGN KEY(document_id,tenant_id) REFERENCES public.documentos(id,tenant_id) ON DELETE CASCADE NOT VALID;
ALTER TABLE public.analisis ADD CONSTRAINT directa_analisis_document_tenant_fk
 FOREIGN KEY(document_id,tenant_id) REFERENCES public.documentos(id,tenant_id) ON DELETE CASCADE NOT VALID;
-- La FK anterior de valoraciones mantiene ON DELETE SET NULL para document_id.
ALTER TABLE public.valoraciones ADD CONSTRAINT directa_valoraciones_document_tenant_fk
 FOREIGN KEY(document_id,tenant_id) REFERENCES public.documentos(id,tenant_id) NOT VALID;

-- No etiquetar embeddings históricos con un modelo que no se ha demostrado.
ALTER TABLE public.document_chunks ADD COLUMN embedding_model text;
ALTER TABLE public.document_chunks ADD CONSTRAINT directa_chunks_model_required
 CHECK(embedding IS NULL OR (embedding_model IS NOT NULL AND embedding_model='nvidia/nemotron-3-embed-1b')) NOT VALID;
CREATE INDEX directa_chunks_tenant_document_idx ON public.document_chunks(tenant_id,document_id);
CREATE INDEX directa_analisis_tenant_document_idx ON public.analisis(tenant_id,document_id);
CREATE UNIQUE INDEX directa_tono_one_approved ON public.perfiles_tono(tenant_id)
 WHERE estado='aprobado' AND tenant_id IS NOT NULL;

CREATE FUNCTION directa_private.protect_identity_columns()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $fn$
BEGIN
  IF OLD.tenant_id IS NOT NULL AND OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'No se permite transferir un recurso de organización' USING ERRCODE='42501';
  END IF;
  IF current_user IN ('anon','authenticated') THEN
    IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR (to_jsonb(OLD)->'created_by') IS DISTINCT FROM (to_jsonb(NEW)->'created_by')
       OR (to_jsonb(OLD)->'auth_user_id') IS DISTINCT FROM (to_jsonb(NEW)->'auth_user_id') THEN
      RAISE EXCEPTION 'La identidad y pertenencia no son editables por el cliente' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION directa_private.protect_identity_columns() FROM PUBLIC,anon,authenticated,service_role;
DO $triggers$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono'] LOOP
    EXECUTE format('CREATE TRIGGER directa_identity_immutable BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION directa_private.protect_identity_columns()',t);
  END LOOP;
END $triggers$;

-- Retirar TODAS las políticas previas de estas siete tablas. No se dejan reglas
-- permisivas heredadas que puedan combinarse con OR y reabrir el acceso.
DO $policies$
DECLARE r record; t text; cols text;
BEGIN
  FOR r IN SELECT tablename,policyname FROM pg_policies WHERE schemaname='public'
    AND tablename IN ('usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono') LOOP
    EXECUTE format('DROP POLICY %I ON public.%I',r.policyname,r.tablename);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono','organizations','memberships'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
    SELECT string_agg(quote_ident(a.attname),',') INTO cols FROM pg_attribute a
      WHERE a.attrelid=('public.'||t)::regclass AND a.attnum>0 AND NOT a.attisdropped;
    EXECUTE format('REVOKE ALL (%s) ON public.%I FROM PUBLIC,anon,authenticated',cols,t);
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
  END LOOP;
END $policies$;
CREATE POLICY directa_org_read ON public.organizations FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(id,'documents.read'));
-- La membresía propia se puede consultar antes de MFA para orientar el enrolamiento.
-- No contiene documentación y ningún cliente puede crear o elevar membresías.
CREATE POLICY directa_member_read ON public.memberships FOR SELECT TO authenticated
 USING(user_id=auth.uid() OR directa_private.can_access_tenant(tenant_id,'members.read'));
CREATE POLICY directa_profile_read ON public.usuarios FOR SELECT TO authenticated
 USING(auth_user_id=auth.uid() AND directa_private.can_access_tenant(tenant_id,'documents.read'));
CREATE POLICY directa_document_read ON public.documentos FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'documents.read'));
CREATE POLICY directa_document_insert ON public.documentos FOR INSERT TO authenticated
 WITH CHECK(tenant_id IS NOT NULL AND created_by=auth.uid()
   AND estado='Procesando' AND directa_private.can_access_tenant(tenant_id,'documents.write'));
CREATE POLICY directa_document_update ON public.documentos FOR UPDATE TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'documents.write'))
 WITH CHECK(directa_private.can_access_tenant(tenant_id,'documents.write'));
CREATE POLICY directa_document_delete ON public.documentos FOR DELETE TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'documents.delete'));
GRANT INSERT,DELETE ON public.documentos TO authenticated;
GRANT UPDATE(titulo) ON public.documentos TO authenticated;
CREATE POLICY directa_chunks_read ON public.document_chunks FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'documents.read') AND EXISTS(
   SELECT 1 FROM public.documentos d WHERE d.id=document_id AND d.tenant_id=document_chunks.tenant_id));
CREATE POLICY directa_analysis_read ON public.analisis FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'analysis.read') AND EXISTS(
   SELECT 1 FROM public.documentos d WHERE d.id=document_id AND d.tenant_id=analisis.tenant_id));
CREATE POLICY directa_rating_read ON public.valoraciones FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'documents.read') AND
   (created_by=auth.uid() OR directa_private.can_access_tenant(tenant_id,'learning.manage')));
CREATE POLICY directa_rating_insert ON public.valoraciones FOR INSERT TO authenticated
 WITH CHECK(created_by=auth.uid() AND directa_private.can_access_tenant(tenant_id,'documents.read')
   AND document_id IS NOT NULL AND EXISTS(
     SELECT 1 FROM public.documentos d WHERE d.id=document_id AND d.tenant_id=valoraciones.tenant_id));
CREATE POLICY directa_rating_delete ON public.valoraciones FOR DELETE TO authenticated
 USING(created_by=auth.uid() AND directa_private.can_access_tenant(tenant_id,'documents.read'));
GRANT INSERT,DELETE ON public.valoraciones TO authenticated;
CREATE POLICY directa_lesson_read ON public.lecciones FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'learning.read'));
CREATE POLICY directa_tone_read ON public.perfiles_tono FOR SELECT TO authenticated
 USING(directa_private.can_access_tenant(tenant_id,'learning.read'));
REVOKE ALL ON public.organizations,public.memberships FROM service_role;
-- Sin GRANT de escritura a authenticated para chunks, análisis, lecciones,
-- perfiles o membresías. El backend nuevo autorizará cada tarea de worker.

-- Preservar firma, salida, 2048 dimensiones y operador coseno de la RPC.
DO $vector_rpc$
DECLARE s text;
BEGIN
 SELECT n.nspname INTO s FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='vector';
 EXECUTE format($ddl$
 CREATE OR REPLACE FUNCTION public.match_document_chunks(
   query_embedding %1$I.vector(2048),match_threshold double precision,
   match_count integer,p_document_id text)
 RETURNS TABLE(id uuid,content text,page_number integer,entity text,similarity double precision)
 LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,public,%1$I
 AS $body$
 BEGIN
   IF query_embedding IS NULL OR %1$I.vector_dims(query_embedding)<>2048
      OR %1$I.vector_norm(query_embedding)=0 THEN
     RAISE EXCEPTION 'El embedding de consulta debe tener 2048 dimensiones y norma no nula' USING ERRCODE='22023';
   END IF;
   IF match_count IS NULL OR match_count NOT BETWEEN 1 AND 100
      OR match_threshold IS NULL OR match_threshold NOT BETWEEN -1 AND 1
      OR p_document_id IS NULL OR length(p_document_id) NOT BETWEEN 1 AND 200 THEN
     RAISE EXCEPTION 'Parámetros de búsqueda inválidos' USING ERRCODE='22023';
   END IF;
   RETURN QUERY SELECT dc.id,dc.content,dc.page_number,dc.entity,
     (1-(dc.embedding::%1$I.halfvec(2048) OPERATOR(%1$I.<=>) query_embedding::%1$I.halfvec(2048)))::double precision
   FROM public.document_chunks dc JOIN public.documentos d
     ON d.id=dc.document_id AND d.tenant_id=dc.tenant_id
   WHERE dc.document_id=p_document_id
     AND dc.embedding_model='nvidia/nemotron-3-embed-1b'
     AND directa_private.can_access_tenant(d.tenant_id,'documents.read')
     AND (1-(dc.embedding::%1$I.halfvec(2048) OPERATOR(%1$I.<=>) query_embedding::%1$I.halfvec(2048)))>match_threshold
   ORDER BY dc.embedding::%1$I.halfvec(2048) OPERATOR(%1$I.<=>) query_embedding::%1$I.halfvec(2048),dc.id
   LIMIT match_count;
 END $body$;
 $ddl$,s);
 EXECUTE format('REVOKE ALL ON FUNCTION public.match_document_chunks(%I.vector,double precision,integer,text) FROM PUBLIC,anon,service_role',s);
 EXECUTE format('GRANT EXECUTE ON FUNCTION public.match_document_chunks(%I.vector,double precision,integer,text) TO authenticated',s);
END $vector_rpc$;

CREATE FUNCTION directa_private.block_audit_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN RAISE EXCEPTION 'El registro de seguridad es append-only' USING ERRCODE='42501'; END $fn$;
REVOKE ALL ON FUNCTION directa_private.block_audit_mutation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER directa_audit_append_only BEFORE UPDATE OR DELETE ON directa_private.security_audit
 FOR EACH ROW EXECUTE FUNCTION directa_private.block_audit_mutation();
INSERT INTO directa_private.migration_log(migration_id,source_commit)
 VALUES('001_identity_tenants_rls_vector','2f3f3d5dbda14ff6580cc6024b89358d3e1c186d');

-- La transacción se cancela si el número de filas ha cambiado.
DO $preservation$
DECLARE r record; n bigint;
BEGIN
 FOR r IN SELECT * FROM directa_private.baseline_counts LOOP
   EXECUTE format('SELECT count(*) FROM public.%I',r.table_name) INTO n;
   IF n<>r.rows_before THEN RAISE EXCEPTION 'Conteo alterado en %',r.table_name; END IF;
 END LOOP;
END $preservation$;
COMMIT;
SELECT migration_id,applied_at FROM directa_private.migration_log ORDER BY applied_at;
