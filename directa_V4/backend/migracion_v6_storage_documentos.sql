-- ============================================================================
-- DIRECTA GG · MIGRACIÓN v6: copia del PDF original para el lector (páginas tal cual).
-- Supabase → SQL Editor → pega este archivo → Run. Se puede correr más de una vez.
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', false)
on conflict (id) do nothing;

-- El backend usa la key pública (anon/publishable), así que necesita permiso sobre este bucket.
-- Igual que las demás tablas del proyecto: acceso abierto para el backend (no es público por URL).
drop policy if exists "directa documentos leer" on storage.objects;
drop policy if exists "directa documentos subir" on storage.objects;
drop policy if exists "directa documentos actualizar" on storage.objects;
drop policy if exists "directa documentos borrar" on storage.objects;
create policy "directa documentos leer" on storage.objects for select to anon, authenticated using (bucket_id = 'documentos');
create policy "directa documentos subir" on storage.objects for insert to anon, authenticated with check (bucket_id = 'documentos');
create policy "directa documentos actualizar" on storage.objects for update to anon, authenticated using (bucket_id = 'documentos');
create policy "directa documentos borrar" on storage.objects for delete to anon, authenticated using (bucket_id = 'documentos');

-- Comprobación: debe aparecer el bucket "documentos"
select id, public from storage.buckets where id = 'documentos';
