-- Step 1: Remove from publication first (table still exists as dim_program_goal)
ALTER PUBLICATION powersync DROP TABLE public.dim_program_goal;

-- Step 2: Rename the table
ALTER TABLE public.dim_program_goal RENAME TO fact_program_goal;

-- Step 3: Drop old FK (dim_program_goal_program_id_fkey → dim_program), add new column + FK
ALTER TABLE public.fact_program_goal
  DROP COLUMN program_id,
  ADD COLUMN program_run_id text;

ALTER TABLE public.fact_program_goal
  ADD CONSTRAINT fact_program_goal_run_fkey
    FOREIGN KEY (program_run_id) REFERENCES public.fact_program_run(program_run_id);

-- Step 4: Re-add to publication under new name
ALTER PUBLICATION powersync ADD TABLE public.fact_program_goal;
