-- PRs are derived client-side and generated on every device. Two devices
-- computing the same PR from the same source set produce different pr_id
-- uuids, so without server-side dedup the same achievement would be written
-- twice. The natural key (workout_set_id, pr_type, target_reps,
-- target_weight) is deterministic for a given set, so we dedup on it.
--
-- 1. Collapse any existing duplicates (keep the highest pr_id per key).
-- 2. Enforce the natural key with a partial unique index (source sets always
--    have a workout_set_id; leave null-key rows unconstrained).
-- 3. A BEFORE INSERT trigger deletes any conflicting natural-key row first so
--    the PowerSync upsert path (conflict target = pr_id) never trips the
--    index when a second device uploads the same PR with a different id.

delete from public.fact_pr a
using public.fact_pr b
where a.pr_id < b.pr_id
  and a.workout_set_id is not distinct from b.workout_set_id
  and a.pr_type = b.pr_type
  and a.target_reps is not distinct from b.target_reps
  and a.target_weight is not distinct from b.target_weight;

create unique index fact_pr_natural_key_uq
  on public.fact_pr (workout_set_id, pr_type, target_reps, target_weight)
  where workout_set_id is not null;

create or replace function public.fact_pr_dedup()
returns trigger
language plpgsql
as $$
begin
  delete from public.fact_pr
  where pr_id <> new.pr_id
    and workout_set_id is not distinct from new.workout_set_id
    and pr_type = new.pr_type
    and target_reps is not distinct from new.target_reps
    and target_weight is not distinct from new.target_weight;
  return new;
end;
$$;

create trigger fact_pr_dedup_trigger
  before insert on public.fact_pr
  for each row execute function public.fact_pr_dedup();
