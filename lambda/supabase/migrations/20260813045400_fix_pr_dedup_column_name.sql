-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.

-- The session-model rename changed fact_pr.workout_set_id -> session_set_id,
-- but Postgres does not rewrite trigger function bodies on column rename.
-- Every fact_pr INSERT was erroring until now.
create or replace function public.fact_pr_dedup()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.fact_pr
  where pr_id <> new.pr_id
    and session_set_id is not distinct from new.session_set_id
    and pr_type = new.pr_type
    and target_reps is not distinct from new.target_reps
    and target_weight is not distinct from new.target_weight;
  return new;
end;
$$;
