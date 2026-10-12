-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.

-- Lessons gain session attribution: which logged session they were created in.
-- Nullable — planner-created lessons have no logged session to link.
-- ON DELETE SET NULL: a cancelled session removes the link but not the
-- lesson (durable per-exercise knowledge).
alter table public.dim_lesson
  add column if not exists session_id text
  references public.fact_session(session_id) on delete set null;
