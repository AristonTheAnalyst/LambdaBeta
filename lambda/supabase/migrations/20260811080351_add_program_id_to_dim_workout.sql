-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.

ALTER TABLE dim_workout ADD COLUMN IF NOT EXISTS program_id TEXT;
ALTER TABLE dim_workout ADD COLUMN IF NOT EXISTS sequence_order INTEGER;
ALTER TABLE dim_workout ADD COLUMN IF NOT EXISTS day_of_week SMALLINT CHECK (day_of_week >= 1 AND day_of_week <= 7);
