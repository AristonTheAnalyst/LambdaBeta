-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.
--
-- Historical note: this file predates the session-model redesign, so it still
-- references the pre-rename table names (fact_workout, dim_planned_workout,
-- ...). It is kept as applied — it is never re-run.

-- =============================================================================
-- Schema Standardization — type consistency, RLS cleanup, coaching readiness
-- All tables are empty; no data migration risk.
-- =============================================================================

-- 1A. Fix fact_bodyweight PK to text (was the only integer serial PK) ----------
ALTER TABLE public.fact_bodyweight
  ALTER COLUMN user_weight_id DROP DEFAULT,
  ALTER COLUMN user_weight_id TYPE text USING user_weight_id::text;
DROP SEQUENCE IF EXISTS fact_user_weight_user_weight_id_seq;

-- 1B. Standardize is_active to boolean everywhere ------------------------------
ALTER TABLE public.dim_workout
  ALTER COLUMN is_active DROP DEFAULT,
  ALTER COLUMN is_active TYPE boolean USING (is_active != 0),
  ALTER COLUMN is_active SET DEFAULT true;

ALTER TABLE public.dim_workout_set
  ALTER COLUMN is_active DROP DEFAULT,
  ALTER COLUMN is_active TYPE boolean USING (is_active != 0),
  ALTER COLUMN is_active SET DEFAULT true;

ALTER TABLE public.fact_pr
  ALTER COLUMN is_active DROP DEFAULT,
  ALTER COLUMN is_active TYPE boolean USING (is_active != 0),
  ALTER COLUMN is_active SET DEFAULT true;

-- 1C. Fix dim_workout_set array columns (text → integer[]) --------------------
-- Table is empty — drop and re-add the columns
ALTER TABLE public.dim_workout_set DROP COLUMN target_reps;
ALTER TABLE public.dim_workout_set ADD COLUMN target_reps integer[];

ALTER TABLE public.dim_workout_set DROP COLUMN target_duration_seconds;
ALTER TABLE public.dim_workout_set ADD COLUMN target_duration_seconds integer[];

-- 1D. Drop duplicate RLS policies ----------------------------------------------
-- dim_exercise
DROP POLICY IF EXISTS "Users can create custom exercises" ON public.dim_exercise;
DROP POLICY IF EXISTS "Users can delete own custom exercises" ON public.dim_exercise;
DROP POLICY IF EXISTS "Users can update own custom exercises" ON public.dim_exercise;
DROP POLICY IF EXISTS "Users can view own custom exercises" ON public.dim_exercise;

-- dim_variation
DROP POLICY IF EXISTS "Users can create custom variations" ON public.dim_variation;
DROP POLICY IF EXISTS "Users can delete own custom variations" ON public.dim_variation;
DROP POLICY IF EXISTS "Users can update own custom variations" ON public.dim_variation;
DROP POLICY IF EXISTS "Users can view own custom variations" ON public.dim_variation;

-- dim_exercise_variation_bridge
DROP POLICY IF EXISTS "Users can create exercise-variation links" ON public.dim_exercise_variation_bridge;
DROP POLICY IF EXISTS "Users can delete own exercise-variation links" ON public.dim_exercise_variation_bridge;
DROP POLICY IF EXISTS "Users can update own exercise-variation links" ON public.dim_exercise_variation_bridge;
DROP POLICY IF EXISTS "Users can view own exercise-variation links" ON public.dim_exercise_variation_bridge;

-- dim_user
DROP POLICY IF EXISTS "Users can insert own profile" ON public.dim_user;
DROP POLICY IF EXISTS "Users can update own profile" ON public.dim_user;
DROP POLICY IF EXISTS "Users can view own profile" ON public.dim_user;

-- fact_bodyweight
DROP POLICY IF EXISTS "Users can delete own weight entries" ON public.fact_bodyweight;
DROP POLICY IF EXISTS "Users can insert own weight entries" ON public.fact_bodyweight;
DROP POLICY IF EXISTS "Users can update own weight entries" ON public.fact_bodyweight;
DROP POLICY IF EXISTS "Users can view own weight entries" ON public.fact_bodyweight;

-- fact_workout
DROP POLICY IF EXISTS "Users can delete own workouts" ON public.fact_workout;
DROP POLICY IF EXISTS "Users can insert own workouts" ON public.fact_workout;
DROP POLICY IF EXISTS "Users can update own workouts" ON public.fact_workout;
DROP POLICY IF EXISTS "Users can view own workouts" ON public.fact_workout;

-- fact_workout_set
DROP POLICY IF EXISTS "Users can delete own workout sets" ON public.fact_workout_set;
DROP POLICY IF EXISTS "Users can insert own workout sets" ON public.fact_workout_set;
DROP POLICY IF EXISTS "Users can update own workout sets" ON public.fact_workout_set;
DROP POLICY IF EXISTS "Users can view own workout sets" ON public.fact_workout_set;

-- dim_program
DROP POLICY IF EXISTS "user_program owner access" ON public.dim_program;

-- dim_planned_workout
DROP POLICY IF EXISTS "program_planned_workout owner access" ON public.dim_planned_workout;

-- dim_planned_set
DROP POLICY IF EXISTS "program_planned_set owner access" ON public.dim_planned_set;

-- fact_program_run
DROP POLICY IF EXISTS "user_program_run owner access" ON public.fact_program_run;

-- coaching_relationship
DROP POLICY IF EXISTS "coaching_relationship coach manage" ON public.coaching_relationship;
DROP POLICY IF EXISTS "coaching_relationship athlete access" ON public.coaching_relationship;

-- 1E. Add coach-access RLS policies (read-only SELECT for coach's athletes) ---
DO $$ BEGIN
  CREATE POLICY "fact_rest coach access" ON public.fact_rest FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.coaching_relationship cr
      WHERE cr.coach_user_id = auth.uid() AND cr.athlete_user_id = fact_rest.user_id));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "fact_program_run coach access" ON public.fact_program_run FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.coaching_relationship cr
      WHERE cr.coach_user_id = auth.uid() AND cr.athlete_user_id = fact_program_run.user_id));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "dim_planned_workout coach access" ON public.dim_planned_workout FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.coaching_relationship cr
      WHERE cr.coach_user_id = auth.uid() AND cr.athlete_user_id = dim_planned_workout.user_id));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "dim_planned_set coach access" ON public.dim_planned_set FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.coaching_relationship cr
      WHERE cr.coach_user_id = auth.uid() AND cr.athlete_user_id = dim_planned_set.user_id));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Publication: re-add tables that had column type changes --------------------
DO $$ BEGIN ALTER PUBLICATION powersync ADD TABLE public.fact_bodyweight; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION powersync ADD TABLE public.dim_workout; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION powersync ADD TABLE public.dim_workout_set; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION powersync ADD TABLE public.fact_pr; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
