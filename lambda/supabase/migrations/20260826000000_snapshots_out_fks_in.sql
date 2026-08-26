-- =============================================================================
-- 2026-08-26: names live in the dims, facts reference them by FK.
--
-- Decision: renaming an exercise or variation updates ALL past data attached
-- to it (users treat names as labels, not historical facts — the rename flow
-- warns them). Dims are archive-only (never hard-deleted), so FKs from fact
-- rows can never dangle.
--
--   * fact_session_exercise.custom_exercise_id → dim_exercise
--   * fact_session_exercise_set.custom_variation_id → dim_variation
--   (the dim side already had its FKs)
--   * Name snapshot columns dropped everywhere:
--       fact_session_exercise.exercise_name
--       fact_session_exercise_set.variation_name
--       dim_planned_session_exercise.exercise_name
--       dim_planned_session_exercise_set.variation_name
--
-- Names now resolve live through the FK joins. Client pairing: database.dart
-- adds 23503 (FK violation) to the fatal upload codes so a would-be violation
-- quarantines visibly instead of stalling the sync checkpoint forever.
-- =============================================================================

-- ── 1. FKs on the fact side ──────────────────────────────────────────────────

alter table public.fact_session_exercise
  add constraint fact_session_exercise_custom_exercise_id_fkey
    foreign key (custom_exercise_id) references public.dim_exercise (custom_exercise_id);

alter table public.fact_session_exercise_set
  add constraint fact_session_exercise_set_custom_variation_id_fkey
    foreign key (custom_variation_id) references public.dim_variation (custom_variation_id);

-- ── 2. Drop the name snapshots ───────────────────────────────────────────────

alter table public.fact_session_exercise drop column exercise_name;
alter table public.fact_session_exercise_set drop column variation_name;
alter table public.dim_planned_session_exercise drop column exercise_name;
alter table public.dim_planned_session_exercise_set drop column variation_name;
