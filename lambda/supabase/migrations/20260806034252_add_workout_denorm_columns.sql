-- Add denormalized name columns to fact_workout so the client can
-- display program/planned-workout names without a JOIN, and so the
-- names survive even if the source program/workout is later deleted.

ALTER TABLE public.fact_workout
  ADD COLUMN IF NOT EXISTS planned_workout_name text,
  ADD COLUMN IF NOT EXISTS program_name text;

-- Ensure the new columns are in the publication for PowerSync
DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE public.fact_workout;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
