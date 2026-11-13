-- SOLO para el laboratorio dedicado directa-login-local.
-- Sin DROP, sin políticas abiertas y sin cambiar tablas preexistentes.
BEGIN;
SET LOCAL search_path=public,extensions;
DO $guard$
DECLARE t text;
BEGIN
 IF to_regnamespace('directa_local_test') IS NOT NULL OR to_regnamespace('directa_private') IS NOT NULL THEN
   RAISE EXCEPTION 'El laboratorio ya fue inicializado; revisar antes de repetir';
 END IF;
 FOREACH t IN ARRAY ARRAY['usuarios','documentos','document_chunks','analisis','valoraciones','lecciones','perfiles_tono','organizations','memberships'] LOOP
   IF to_regclass('public.'||t) IS NOT NULL THEN
     RAISE EXCEPTION 'La base contiene tablas previas; no se sobrescriben';
   END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM auth.users) THEN
   RAISE EXCEPTION 'La instancia contiene usuarios previos y no es un laboratorio vacío';
 END IF;
END $guard$;
CREATE SCHEMA directa_local_test;
REVOKE ALL ON SCHEMA directa_local_test FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE directa_local_test.bootstrap(project_id text PRIMARY KEY);
INSERT INTO directa_local_test.bootstrap VALUES('directa-login-local');
REVOKE ALL ON directa_local_test.bootstrap FROM PUBLIC,anon,authenticated,service_role;
-- 1. EXTENSIÓN VECTORIAL
create extension if not exists vector with schema extensions;

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


ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analisis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.valoraciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lecciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfiles_tono ENABLE ROW LEVEL SECURITY;
COMMIT;
