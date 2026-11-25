-- =====================================================================
-- DIRECTA v9 · Perfiles con RUT único y control de RUT repetido más justo
-- Pegar completo en Supabase → SQL Editor → New query → Run.
-- Requiere haber corrido antes v7 y v8. Se puede correr más de una vez.
--
-- Qué arregla:
--  * El RUT no tenía índice único: dos registros al mismo tiempo podían pasar los dos.
--  * Una cuenta SIN confirmar bloqueaba el RUT para siempre (se podía "apartar" el RUT de otra persona).
--    Ahora solo cuenta si está confirmada o se creó hace menos de 24 horas.
--  * Se elimina la tabla "usuarios", que nada usaba (las cuentas viven en Supabase Auth).
-- =====================================================================

-- 1) Perfil de cada cuenta (datos que no cambian: RUT, empresa y cargo) -------------------
create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null default '',
  rut text not null,
  rut_empresa text not null references public.empresas_autorizadas(rut),
  cargo text not null default 'Gerente General',
  creado_en timestamptz not null default now()
);

create unique index if not exists perfiles_rut_unico on public.perfiles(rut);
create index if not exists perfiles_empresa on public.perfiles(rut_empresa);

-- Solo el backend la lee (clave de servicio); la app no tiene acceso.
alter table public.perfiles enable row level security;
revoke all on public.perfiles from anon, authenticated;
grant all on public.perfiles to service_role;

-- 2) Al crear una cuenta se crea su perfil -----------------------------------------------
-- Si el RUT ya lo tiene una cuenta confirmada o reciente, la creación se rechaza (respaldo del control
-- de v7 cuando dos registros llegan al mismo tiempo). Una cuenta antigua sin confirmar se elimina.
create or replace function public.directa_crear_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rut_n text := public.directa_rut_normal(new.raw_user_meta_data->>'rut');
  emp_n text := public.directa_rut_normal(new.raw_app_meta_data->>'rut_empresa');
begin
  if emp_n = '' or not public.directa_rut_valido(rut_n) then
    return new;  -- sin empresa habilitada no hay perfil; el backend tampoco le da acceso
  end if;

  -- cuentas viejas que nunca confirmaron el correo liberan su RUT
  delete from auth.users u
  using public.perfiles p
  where p.id = u.id and p.rut = rut_n
    and u.email_confirmed_at is null and u.created_at < now() - interval '24 hours';

  insert into public.perfiles (id, nombre, rut, rut_empresa, cargo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', ''), rut_n, emp_n,
          coalesce(nullif(new.raw_user_meta_data->>'cargo', ''), 'Gerente General'));
  return new;
exception when unique_violation then
  raise exception 'DIRECTA: Ya existe una cuenta con ese RUT. Inicia sesión o recupera tu contraseña.';
end;
$$;

drop trigger if exists directa_crear_perfil on auth.users;
create trigger directa_crear_perfil
  after insert on auth.users
  for each row execute function public.directa_crear_perfil();

-- 3) Cuentas que ya existían: se les crea el perfil (si dos comparten RUT, queda la más antigua) ---
insert into public.perfiles (id, nombre, rut, rut_empresa, cargo)
select u.id,
       coalesce(u.raw_user_meta_data->>'nombre', ''),
       public.directa_rut_normal(u.raw_user_meta_data->>'rut'),
       public.directa_rut_normal(u.raw_app_meta_data->>'rut_empresa'),
       coalesce(nullif(u.raw_user_meta_data->>'cargo', ''), 'Gerente General')
from auth.users u
where public.directa_rut_valido(public.directa_rut_normal(u.raw_user_meta_data->>'rut'))
  and exists (select 1 from public.empresas_autorizadas e
              where e.rut = public.directa_rut_normal(u.raw_app_meta_data->>'rut_empresa') and e.activa)
order by u.created_at
on conflict do nothing;

-- 4) Control antes de crear la cuenta (reemplaza al de v7): ahora una cuenta sin confirmar y
--    de más de 24 horas ya no bloquea el RUT -------------------------------------------------
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
             where public.directa_rut_normal(u.raw_user_meta_data->>'rut') = rut_persona
               and (u.email_confirmed_at is not null or u.created_at > now() - interval '24 hours')) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 409,
      'message', 'DIRECTA: Ya existe una cuenta con ese RUT. Inicia sesión o recupera tu contraseña.'));
  end if;

  return '{}'::jsonb;
end;
$$;

grant execute on function public.directa_antes_de_crear_usuario(jsonb) to supabase_auth_admin;
revoke execute on function public.directa_antes_de_crear_usuario(jsonb) from authenticated, anon, public;

-- 5) Tabla sin uso ---------------------------------------------------------------------------
drop table if exists public.usuarios;

-- Revisión -----------------------------------------------------------------------------------
-- a) Cuentas que se quedaron sin perfil (deben ser solo las que no tienen RUT válido o empresa):
select u.email, u.raw_user_meta_data->>'rut' as rut, u.raw_app_meta_data->>'rut_empresa' as empresa
from auth.users u left join public.perfiles p on p.id = u.id where p.id is null;
-- b) Perfiles creados:
select nombre, rut, rut_empresa, cargo from public.perfiles order by creado_en;
