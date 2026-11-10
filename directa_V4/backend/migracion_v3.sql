-- ============================================================================
-- DIRECTA GG · MIGRACIÓN v3 (verificación, aprendizaje y perfil de tono)
-- Solo AGREGA tablas nuevas. No borra ni cambia las existentes: se puede correr sobre la base
-- que ya tienes con documentos y análisis. (NO vuelvas a correr base_de_datos.sql: ese archivo
-- empieza borrando todas las tablas.)
-- Supabase → SQL Editor → pega este archivo → Run.
-- ============================================================================

-- 1. VALORACIONES (pulgares bajo cada respuesta)
create table if not exists valoraciones (
    id uuid primary key default gen_random_uuid(),
    document_id text references documentos(id) on delete set null,
    agente text not null default 'general',
    pregunta text,
    respuesta text,
    valor integer not null check (valor in (1, -1)),
    motivo text,
    sello text,
    mensaje_id text,
    usada_en_leccion boolean not null default false,
    creado_en timestamptz default now()
);
create index if not exists idx_valoraciones_agente on valoraciones(agente);
create index if not exists idx_valoraciones_documento on valoraciones(document_id);
create index if not exists idx_valoraciones_mensaje on valoraciones(mensaje_id);

-- 2. LECCIONES POR AGENTE (pendiente → aprobada / rechazada / revertida; versionadas)
create table if not exists lecciones (
    id uuid primary key default gen_random_uuid(),
    agente text not null,
    texto text not null,
    estado text not null default 'pendiente',
    version integer not null default 1,
    historial jsonb not null default '[]'::jsonb,
    origen jsonb not null default '[]'::jsonb,
    prueba jsonb,
    aprobado_en timestamptz,
    revertido_en timestamptz,
    creado_en timestamptz default now()
);
create index if not exists idx_lecciones_agente_estado on lecciones(agente, estado);

-- 3. PERFILES DE TONO DE LA MEMORIA (uno aprobado por empresa; los anteriores quedan como historial)
create table if not exists perfiles_tono (
    id uuid primary key default gen_random_uuid(),
    empresa text not null default 'principal',
    version integer not null default 1,
    estado text not null default 'borrador',
    perfil jsonb not null default '{}'::jsonb,
    medidas jsonb not null default '{}'::jsonb,
    corpus jsonb not null default '[]'::jsonb,
    editado boolean not null default false,
    aviso text,
    actualizado_en timestamptz default now(),
    aprobado_en timestamptz,
    creado_en timestamptz default now()
);
create index if not exists idx_perfiles_tono_empresa on perfiles_tono(empresa, estado);

-- 4. SEGURIDAD (igual que el MVP: lectura y escritura abiertas; cambiar antes de usar datos reales)
alter table valoraciones  enable row level security;
alter table lecciones     enable row level security;
alter table perfiles_tono enable row level security;

drop policy if exists "Todo valoraciones" on valoraciones;
drop policy if exists "Todo lecciones" on lecciones;
drop policy if exists "Todo perfiles_tono" on perfiles_tono;
create policy "Todo valoraciones"  on valoraciones  for all using (true) with check (true);
create policy "Todo lecciones"     on lecciones     for all using (true) with check (true);
create policy "Todo perfiles_tono" on perfiles_tono for all using (true) with check (true);

-- Comprobación: debe listar las tres tablas
select table_name from information_schema.tables
where table_schema = 'public' and table_name in ('valoraciones', 'lecciones', 'perfiles_tono');
