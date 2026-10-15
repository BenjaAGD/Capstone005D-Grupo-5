
-- 0. LIMPIAR VERSIONES ANTERIORES
drop table if exists analisis cascade;
drop table if exists document_chunks cascade;
drop table if exists documentos cascade;
drop table if exists usuarios cascade;
drop function if exists match_document_chunks(vector, float, int, text);

-- 1. EXTENSIÓN VECTORIAL
create extension if not exists vector;

-- 2. TABLA USUARIOS 
create table usuarios (
    id uuid primary key default gen_random_uuid(),
    nombre text not null,
    correo text unique not null,
    rol text not null default 'gerente_general',
    creado_en timestamptz default now()
);

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

-- 7. ROW LEVEL SECURITY
alter table usuarios        enable row level security;
alter table documentos      enable row level security;
alter table document_chunks enable row level security;
alter table analisis        enable row level security;

-- 8. POLÍTICAS (MVP: lectura y escritura abiertas)
create policy "Leer usuarios"        on usuarios        for select using (true);
create policy "Leer documentos"      on documentos      for select using (true);
create policy "Leer chunks"          on document_chunks for select using (true);
create policy "Leer analisis"        on analisis        for select using (true);

create policy "Insertar usuarios"    on usuarios        for insert with check (true);
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

