-- Migración v5 · orden de los fragmentos dentro de cada página (lector del documento).
-- Es OPCIONAL y segura: el backend funciona sin ella (el orden dentro de una página queda como antes).
-- Ejecutar una vez en Supabase → SQL Editor.
--
-- Los documentos que ya estaban cargados quedan con orden NULL (se muestran como hasta ahora).
-- Los documentos que se suban desde ahora guardan el orden correcto.
-- Para ordenar un documento antiguo, bórralo y vuelve a subirlo.

alter table document_chunks add column if not exists orden integer;

create index if not exists idx_document_chunks_doc_pagina_orden
    on document_chunks (document_id, page_number, orden);
