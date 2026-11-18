-- DIRECTA GG · Migración v4: diagnóstico individual del análisis por agente
-- Ejecutar una sola vez en Supabase → SQL Editor. No modifica las tablas actuales.

create table if not exists analisis_diagnosticos (
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

create index if not exists idx_analisis_diagnosticos_documento
    on analisis_diagnosticos(document_id);

alter table analisis_diagnosticos enable row level security;
drop policy if exists "Todo diagnosticos analisis" on analisis_diagnosticos;
create policy "Todo diagnosticos analisis" on analisis_diagnosticos
    for all using (true) with check (true);
