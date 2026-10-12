-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.
--
-- Note: this file is why the local `20260808000000_pr_propagated_flag.sql`
-- (never applied to the cloud) was safe to delete — its intent, adding
-- `fact_pr.is_propagated`, is carried out here.

-- Follow-up: rename stale reference columns on tables that weren't part of the
-- main rename, and apply the unapplied pr_propagated flag migration.
alter table public.fact_rest rename column user_workout_id to session_id;
alter table public.fact_pr rename column workout_set_id to session_set_id;
alter table public.fact_pr add column if not exists is_propagated integer not null default 0;
