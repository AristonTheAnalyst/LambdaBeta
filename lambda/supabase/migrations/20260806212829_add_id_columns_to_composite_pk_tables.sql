-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.

-- Add id columns to composite-PK tables so PowerSync uploads (which
-- always include the synthetic id column) don't fail with "column does
-- not exist". The columns are nullable text — they accept whatever
-- PowerSync sends but store nothing meaningful server-side.
ALTER TABLE public.dim_exercise_variation_bridge
  ADD COLUMN IF NOT EXISTS id text;

ALTER TABLE public.coaching_relationship
  ADD COLUMN IF NOT EXISTS id text;

-- Re-add to publication (column change may have affected it)
DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE public.dim_exercise_variation_bridge;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE public.coaching_relationship;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
