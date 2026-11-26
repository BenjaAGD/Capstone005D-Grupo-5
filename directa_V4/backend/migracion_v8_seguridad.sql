-- =====================================================================
-- DIRECTA v8 · Seguridad: tablas cerradas y documentos con dueño (empresa)
-- Pegar completo en Supabase → SQL Editor → New query → Run.
-- Requiere haber corrido antes v6 y v7. Se puede correr más de una vez.
--
-- ORDEN DE DESPLIEGUE (importante):
--   1) Pon SUPABASE_SERVICE_ROLE_KEY en Render (Environment) y despliega el backend nuevo.
--   2) Recién después corre este archivo. Si lo corres antes, el backend viejo (que usa la
--      clave pública) deja de poder leer las tablas.
--   Esta migración NO borra documentos ni análisis existentes: solo les agrega dueño.
-- =====================================================================

-- 1) Dueño de cada documento ------------------------------------------------
alter table public.documentos
  add column if not exists empresa_rut text references public.empresas_autorizadas(rut),
  add column if not exists subido_por uuid references auth.users(id) on delete set null;

-- Los documentos que ya existían son de la única empresa del prototipo.
update public.documentos set empresa_rut = '76123456-0' where empresa_rut is null;

create index if not exists idx_documentos_empresa on public.documentos(empresa_rut);

-- 2) La empresa de la cuenta va en app_metadata (la persona NO puede editarlo) ---------
-- El control de registro (v7) ya validó la empresa; este trigger solo copia ese dato a un lugar
-- que el usuario no puede modificar desde la app. El backend lee la empresa de ahí.
create or replace function public.directa_copiar_empresa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rut_emp text := public.directa_rut_normal(new.raw_user_meta_data->>'rut_empresa');
begin
  if public.directa_rut_valido(rut_emp)
     and exists (select 1 from public.empresas_autorizadas e where e.rut = rut_emp and e.activa) then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object('rut_empresa', rut_emp,
                            'rut', public.directa_rut_normal(new.raw_user_meta_data->>'rut'));
  end if;
  return new;
end;
$$;

drop trigger if exists directa_copiar_empresa on auth.users;
create trigger directa_copiar_empresa
  before insert on auth.users
  for each row execute function public.directa_copiar_empresa();

-- Cuentas que ya existen. Las que se registraron con RUT de empresa (v7) conservan esa empresa.
-- Las anteriores a v7 no tenían empresa: se asignan a Directa Demo SpA, la única del prototipo.
-- (Si alguna cuenta NO debe entrar, bórrala en Authentication → Users antes de correr esto.)
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(
      'rut_empresa',
      case when public.directa_rut_valido(public.directa_rut_normal(raw_user_meta_data->>'rut_empresa'))
                and exists (select 1 from public.empresas_autorizadas e
                            where e.rut = public.directa_rut_normal(raw_user_meta_data->>'rut_empresa') and e.activa)
           then public.directa_rut_normal(raw_user_meta_data->>'rut_empresa')
           else '76123456-0' end)
where coalesce(raw_app_meta_data->>'rut_empresa', '') = '';

-- 3) Cerrar las tablas: sin políticas ni permisos para anon/authenticated ------------------
-- La app nunca lee las tablas directo (todo pasa por el backend, que usa la clave de servicio,
-- que se salta RLS). Antes todas tenían políticas "using (true)": cualquiera con la clave pública
-- de la app podía leer y borrar todo.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('usuarios', 'documentos', 'document_chunks', 'analisis', 'analisis_diagnosticos',
                        'valoraciones', 'lecciones', 'perfiles_tono')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array['usuarios', 'documentos', 'document_chunks', 'analisis', 'analisis_diagnosticos',
                           'valoraciones', 'lecciones', 'perfiles_tono']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('revoke all on public.%I from anon, authenticated', t);
      execute format('grant all on public.%I to service_role', t);
    end if;
  end loop;
end $$;

-- La búsqueda vectorial solo la usa el backend.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'match_document_chunks'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.f);
    execute format('grant execute on function %s to service_role', r.f);
  end loop;
end $$;

-- Los PDF originales (bucket "documentos"): solo el backend, no anon ni authenticated.
drop policy if exists "directa documentos leer" on storage.objects;
drop policy if exists "directa documentos subir" on storage.objects;
drop policy if exists "directa documentos actualizar" on storage.objects;
drop policy if exists "directa documentos borrar" on storage.objects;

-- Revisión -----------------------------------------------------------------
-- a) Debe devolver 0 filas: ninguna tabla tiene políticas abiertas.
select tablename, policyname from pg_policies
where schemaname = 'public'
  and tablename in ('usuarios', 'documentos', 'document_chunks', 'analisis', 'analisis_diagnosticos',
                    'valoraciones', 'lecciones', 'perfiles_tono');
-- b) Todas las cuentas deben tener empresa.
select email, raw_app_meta_data->>'rut_empresa' as empresa from auth.users order by created_at;
-- c) Todos los documentos deben tener empresa.
select count(*) filter (where empresa_rut is null) as sin_empresa, count(*) as total from public.documentos;
