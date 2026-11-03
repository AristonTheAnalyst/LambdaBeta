-- 2026-10-26: multi-set goals — a goal's requirement list moves off the one
-- target pair and into a child table.
--
-- The rule (locked 2026-10-25): a multi-set goal lists per-set requirements,
-- each "THIS SET OR BETTER" (weight >= w and reps >= r), and ALL of them must
-- be met by DISTINCT sets in the window. It is one goal — one exercise, one
-- variation, one deadline, one description — that happens to name several
-- rungs of the climb, so the requirements belong to the goal the way a
-- planned session's sets belong to the planned session.
--
-- SINGLE-SET GOALS ARE UNTOUCHED. The parent's target_weight / target_reps
-- stay the single-set target exactly as before (both nullable already), and a
-- single-set goal writes NO child rows. A multi-set goal leaves both parent
-- columns NULL and writes its whole list here. One truth per shape:
-- `targets.isNotEmpty` means "read the child table", otherwise the parent
-- columns are the target. Nothing is mirrored onto the parent — a mirrored
-- copy would be a second answer to the same question.
--
-- ON DELETE CASCADE on both edges: a goal is a fact and facts hard-delete
-- (the Goals tab's swipe), and an account deletion is a cascade the way every
-- other user-owned table takes one. The client has no constraints at all, so
-- the repository mirrors both deletes by hand — the local rows are what the
-- UI reads (sync-contract, "Deleting rows: the client has no constraints").

create table public.fact_goal_target (
  goal_target_id text primary key,
  goal_id text not null references public.fact_goal (goal_id) on delete cascade,
  user_id uuid not null references public.dim_user (user_id) on delete cascade,
  -- 1-based, dense, the order the requirements are listed and matched in.
  target_set_order integer not null,
  target_weight numeric,
  target_reps integer
);

-- The only read: one goal's requirements, in order.
create index fact_goal_target_goal_idx
  on public.fact_goal_target (goal_id, target_set_order);

-- The friends stream pages children by user, one bucket per friend.
create index fact_goal_target_user_idx
  on public.fact_goal_target (user_id);

alter table public.fact_goal_target enable row level security;

create policy "fact_goal_target owner access"
  on public.fact_goal_target for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Coach SELECT parity with every other athlete-owned table (2026-08-13).
do $$ begin create policy "fact_goal_target coach access" on public.fact_goal_target for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = fact_goal_target.user_id)); exception when duplicate_object then null; end $$;

grant select, insert, update, delete on public.fact_goal_target to anon, authenticated;

alter publication powersync add table public.fact_goal_target;

comment on table public.fact_goal_target is
  'A multi-set goal''s requirements: each row is "this set or better" '
  '(weight >= target_weight and reps >= target_reps), and one session must '
  'meet every row with a distinct set. Single-set goals keep the parent''s '
  'target_weight/target_reps and have no rows here.';
