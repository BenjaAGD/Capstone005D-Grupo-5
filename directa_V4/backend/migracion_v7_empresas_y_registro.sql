-- =====================================================================
-- DIRECTA v7 · Empresas autorizadas y control de registro
-- Pegar completo en Supabase → SQL Editor → New query → Run.
-- Se puede correr más de una vez sin romper nada.
-- =====================================================================

-- 1) Valida un RUT chileno (módulo 11). Acepta "12.345.678-5" o "12345678-5".
create or replace function public.directa_rut_valido(rut text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  limpio text := upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g'));
  cuerpo text;
  dv text;
  suma int := 0;
  factor int := 2;
  r int;
  esperado text;
begin
  if length(limpio) < 8 or length(limpio) > 9 then return false; end if;
  cuerpo := left(limpio, length(limpio) - 1);
  dv := right(limpio, 1);
  if cuerpo !~ '^[0-9]+$' then return false; end if;
  for i in reverse length(cuerpo)..1 loop
    suma := suma + substr(cuerpo, i, 1)::int * factor;
    factor := case when factor = 7 then 2 else factor + 1 end;
  end loop;
  r := 11 - (suma % 11);
  esperado := case r when 11 then '0' when 10 then 'K' else r::text end;
  return dv = esperado;
end;
$$;

-- Deja el RUT como "12345678-5" (sin puntos, K mayúscula).
create or replace function public.directa_rut_normal(rut text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when length(x) < 2 then ''
    else ltrim(left(x, length(x) - 1), '0') || '-' || right(x, 1)
  end
  from (select upper(regexp_replace(coalesce(rut, ''), '[^0-9kK]', '', 'g')) as x) t;
$$;

-- 2) Empresas habilitadas para usar DIRECTA.
create table if not exists public.empresas_autorizadas (
  rut text primary key check (public.directa_rut_valido(rut)),
  nombre text not null,
  activa boolean not null default true,
  creada_en timestamptz not null default now()
);

-- Solo el sistema la lee: la app no tiene acceso (RLS sin políticas para anon/authenticated).
alter table public.empresas_autorizadas enable row level security;
revoke all on public.empresas_autorizadas from anon, authenticated;

-- Empresa ficticia para el prototipo (RUT inventado con dígito verificador válido).
insert into public.empresas_autorizadas (rut, nombre)
values ('76123456-0', 'Directa Demo SpA')
on conflict (rut) do nothing;

-- 3) Control antes de crear cada usuario (Auth Hook "Before User Created").
create or replace function public.directa_antes_de_crear_usuario(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := coalesce(event->'user'->'user_metadata', event->'user'->'raw_user_meta_data', '{}'::jsonb);
  rut_persona text := public.directa_rut_normal(meta->>'rut');
  rut_empresa text := public.directa_rut_normal(meta->>'rut_empresa');
begin
  if not public.directa_rut_valido(rut_persona) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400,
      'message', 'DIRECTA: Tu RUT no es válido. Revisa el dígito verificador.'));
  end if;

  if not public.directa_rut_valido(rut_empresa) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400,
      'message', 'DIRECTA: El RUT de la empresa no es válido.'));
  end if;

  if not exists (select 1 from public.empresas_autorizadas e where e.rut = rut_empresa and e.activa) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'DIRECTA: Tu empresa no está habilitada en DIRECTA. Pide acceso al administrador.'));
  end if;

  if exists (select 1 from auth.users u
             where public.directa_rut_normal(u.raw_user_meta_data->>'rut') = rut_persona) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 409,
      'message', 'DIRECTA: Ya existe una cuenta con ese RUT. Inicia sesión o recupera tu contraseña.'));
  end if;

  return '{}'::jsonb;
end;
$$;

-- Solo Supabase Auth puede ejecutar el control; nadie más.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.directa_antes_de_crear_usuario(jsonb) to supabase_auth_admin;
grant execute on function public.directa_rut_valido(text) to supabase_auth_admin;
grant execute on function public.directa_rut_normal(text) to supabase_auth_admin;
revoke execute on function public.directa_antes_de_crear_usuario(jsonb) from authenticated, anon, public;
grant select on public.empresas_autorizadas to supabase_auth_admin;
drop policy if exists "auth lee empresas" on public.empresas_autorizadas;
create policy "auth lee empresas" on public.empresas_autorizadas
  as permissive for select to supabase_auth_admin using (true);

-- Revisión: debe mostrar la empresa ficticia.
select rut, nombre, activa from public.empresas_autorizadas;
