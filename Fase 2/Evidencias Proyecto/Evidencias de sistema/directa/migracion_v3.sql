-- ============================================================================
-- DIRECTA v3 — migración ADITIVA (no borra nada; se puede correr más de una vez).
-- Pégala en el SQL Editor de Supabase. Crea las 6 tablas nuevas:
--   documentos_meta       tipo (memoria/informe) y período de cada documento
--   agente_interacciones  cada pregunta/respuesta de los agentes, con su sello de verificación y tu 👍/👎
--   agente_lecciones      reglas de comportamiento que cada agente va aprendiendo (con versiones)
--   perfil_tono           perfil de tono de las memorias anuales (borrador -> aprobado)
--   memoria_borradores    borradores de capítulos de la memoria (y lo que editas a mano)
--   reunion_carpetas      última carpeta "Preparar mi reunión" de cada documento
-- Si estas tablas no existen, la app sigue funcionando y guarda en archivos locales (datos_locales/).
-- ============================================================================

create table if not exists documentos_meta (
    id uuid primary key default gen_random_uuid(),
    document_id text not null unique,
    tipo text not null default 'informe' check (tipo in ('memoria', 'informe')),
    periodo text,
    origen text default 'automatico',
    creado_en timestamptz default now()
);

create table if not exists agente_interacciones (
    id uuid primary key default gen_random_uuid(),
    document_id text,
    agente text not null,
    pregunta text,
    pregunta_id text,
    origen text default 'chat',
    respuesta text,
    sello text,
    puntaje numeric,
    corregida boolean default false,
    problemas jsonb default '[]'::jsonb,
    valoracion integer check (valoracion in (-1, 1)),
    motivo text,
    comentario text,
    valorada_en timestamptz,
    version_lecciones integer default 0,
    creado_en timestamptz default now()
);
create index if not exists idx_interacciones_agente on agente_interacciones(agente, creado_en desc);
create index if not exists idx_interacciones_doc on agente_interacciones(document_id, agente);

create table if not exists agente_lecciones (
    id uuid primary key default gen_random_uuid(),
    agente text not null,
    texto text not null,
    origen text default 'gerente',
    tipo_problema text,
    motivo text,
    soporte integer default 1,
    activa boolean default true,
    eventos jsonb default '[]'::jsonb,
    creado_en timestamptz default now()
);
create index if not exists idx_lecciones_agente on agente_lecciones(agente);

create table if not exists perfil_tono (
    id uuid primary key default gen_random_uuid(),
    version integer not null,
    estado text not null default 'borrador' check (estado in ('borrador', 'aprobado')),
    origen text,
    perfil jsonb default '{}'::jsonb,
    estadisticas jsonb default '{}'::jsonb,
    fuentes jsonb default '[]'::jsonb,
    fuente_datos text,
    aprobado_por text,
    creado_en timestamptz default now()
);

create table if not exists memoria_borradores (
    id uuid primary key default gen_random_uuid(),
    llave text not null unique,
    clave text,
    capitulo_id text not null,
    texto text,
    pendientes jsonb default '[]'::jsonb,
    revision jsonb default '{}'::jsonb,
    tono text,
    estado text default 'generado',
    comparacion_tono jsonb default '{}'::jsonb,
    actualizado_en timestamptz default now(),
    creado_en timestamptz default now()
);
create index if not exists idx_borradores_clave on memoria_borradores(clave);

create table if not exists reunion_carpetas (
    id uuid primary key default gen_random_uuid(),
    document_id text not null unique,
    carpeta jsonb not null,
    actualizado_en timestamptz default now(),
    creado_en timestamptz default now()
);

-- ROW LEVEL SECURITY (MVP: igual que las tablas originales, acceso abierto con la llave de la app).
-- Antes de producción real, reemplaza estas políticas por unas ligadas al usuario autenticado.
do $$
declare t text;
begin
    foreach t in array array['documentos_meta', 'agente_interacciones', 'agente_lecciones',
                             'perfil_tono', 'memoria_borradores', 'reunion_carpetas']
    loop
        execute format('alter table %I enable row level security', t);
        execute format('drop policy if exists "directa_todo" on %I', t);
        execute format('create policy "directa_todo" on %I for all using (true) with check (true)', t);
    end loop;
end $$;
