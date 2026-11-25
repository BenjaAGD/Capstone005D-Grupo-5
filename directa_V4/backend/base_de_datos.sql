
-- 0. LIMPIAR VERSIONES ANTERIORES
drop table if exists analisis_diagnosticos cascade;
drop table if exists valoraciones cascade;
drop table if exists lecciones cascade;
drop table if exists perfiles_tono cascade;
drop table if exists analisis cascade;
drop table if exists document_chunks cascade;
drop table if exists documentos cascade;
drop function if exists match_document_chunks(vector, float, int, text);

-- 1. EXTENSIÓN VECTORIAL
create extension if not exists vector;

-- 2. USUARIOS: viven en Supabase Auth (auth.users); su perfil está en public.perfiles (migracion_v9).

-- 3. TABLA DOCUMENTOS

create table documentos (
    id text primary key,
    titulo text not null,
    nombre_archivo text,
    total_paginas integer,
    estado text default 'Procesando',
    creado_en timestamptz default now()
);

-- 4. TABLA DOCUMENT_CHUNKS (dimensión 2048 — nemotron-3-embed-1b)
create table document_chunks (
    id uuid primary key default gen_random_uuid(),
    document_id text not null
        references documentos(id)
        on delete cascade,
    content text not null,
    page_number integer,
    entity text,
    embedding vector(2048),
    orden integer,  -- orden del fragmento dentro de la página (lo usa el lector)
    creado_en timestamptz default now()
);

-- 5. TABLA ANALISIS (resultados de los 14 agentes)

create table analisis (
    id uuid primary key default gen_random_uuid(),
    document_id text not null
        references documentos(id)
        on delete cascade,
    agente text not null,
    resultado jsonb not null,
    score integer not null default 0,
    creado_en timestamptz default now(),
    constraint analisis_documento_agente_unique
        unique (document_id, agente)
);

-- 6. ÍNDICES
create index idx_document_chunks_document
on document_chunks(document_id);

create index idx_document_chunks_entity
on document_chunks(entity);

-- HNSW sobre halfvec (2048 > 2000 dims requiere cast)
create index idx_document_chunks_embedding
on document_chunks
using hnsw ((embedding::halfvec(2048)) halfvec_cosine_ops);

create index idx_analisis_document
on analisis(document_id);

create index idx_analisis_agente
on analisis(agente);

create index idx_documentos_estado
on documentos(estado);

create index idx_document_chunks_doc_pagina_orden
on document_chunks (document_id, page_number, orden);

-- 7. ROW LEVEL SECURITY
alter table documentos      enable row level security;
alter table document_chunks enable row level security;
alter table analisis        enable row level security;

-- 8. POLÍTICAS (MVP: lectura y escritura abiertas)
create policy "Leer documentos"      on documentos      for select using (true);
create policy "Leer chunks"          on document_chunks for select using (true);
create policy "Leer analisis"        on analisis        for select using (true);

create policy "Insertar documentos"  on documentos      for insert with check (true);
create policy "Insertar chunks"      on document_chunks for insert with check (true);
create policy "Insertar analisis"    on analisis        for insert with check (true);

create policy "Actualizar documentos" on documentos     for update using (true);
create policy "Actualizar analisis"   on analisis       for update using (true);

create policy "Eliminar documentos"  on documentos      for delete using (true);
create policy "Eliminar chunks"      on document_chunks for delete using (true);
create policy "Eliminar analisis"    on analisis        for delete using (true);

-- 9. FUNCIÓN DE BÚSQUEDA VECTORIAL
create or replace function match_document_chunks (
    query_embedding vector(2048),
    match_threshold float,
    match_count int,
    p_document_id text
)
returns table (
    id uuid,
    content text,
    page_number integer,
    entity text,
    similarity float
)
language sql
stable
as $$
    select
        dc.id,
        dc.content,
        dc.page_number,
        dc.entity,
        1 - ((dc.embedding::halfvec(2048)) <=> (query_embedding::halfvec(2048))) as similarity
    from document_chunks dc
    where
        dc.document_id = p_document_id
        and 1 - ((dc.embedding::halfvec(2048)) <=> (query_embedding::halfvec(2048))) > match_threshold
    order by
        (dc.embedding::halfvec(2048)) <=> (query_embedding::halfvec(2048))
    limit match_count;
$$;

-- 10. TABLA ANALISIS_DIAGNOSTICOS (estado de cada agente por documento)
create table analisis_diagnosticos (
    document_id text not null references documentos(id) on delete cascade,
    agente text not null,
    estado text not null default 'pendiente'
        check (estado in ('pendiente', 'listo', 'error', 'sin_evidencia', 'sin_detalle')),
    codigo_error text,
    mensaje text,
    intentos integer not null default 0,
    reintentable boolean not null default false,
    actualizado_en timestamptz not null default now(),
    primary key (document_id, agente)
);
create index idx_analisis_diagnosticos_documento on analisis_diagnosticos(document_id);

-- 11. APRENDIZAJE: VALORACIONES, LECCIONES Y PERFILES DE TONO
create table valoraciones (
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
create index idx_valoraciones_agente on valoraciones(agente);
create index idx_valoraciones_documento on valoraciones(document_id);
create index idx_valoraciones_mensaje on valoraciones(mensaje_id);

create table lecciones (
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
create index idx_lecciones_agente_estado on lecciones(agente, estado);

create table perfiles_tono (
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
create index idx_perfiles_tono_empresa on perfiles_tono(empresa, estado);

-- 12. RLS Y POLÍTICAS DE LAS TABLAS NUEVAS (MVP: abiertas)
alter table analisis_diagnosticos enable row level security;
alter table valoraciones          enable row level security;
alter table lecciones             enable row level security;
alter table perfiles_tono         enable row level security;

create policy "Todo diagnosticos analisis" on analisis_diagnosticos for all using (true) with check (true);
create policy "Todo valoraciones"          on valoraciones          for all using (true) with check (true);
create policy "Todo lecciones"             on lecciones             for all using (true) with check (true);
create policy "Todo perfiles_tono"         on perfiles_tono         for all using (true) with check (true);
