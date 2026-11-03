-- 2026-10-26: a friend reads a goal's requirement rungs with the goal.
--
-- The friends_data stream already sends every mutual friend's
-- fact_goal_target rows (2026-10-26, ride-along with fact_goal) — a goal row
-- without its rungs would read as a goal with no target. Streams bypass RLS,
-- so that send needed no policy; this is the REST defence catching up with
-- what the stream already promises, exactly as 20261023120000_friends.sql
-- did for the seven tables a friend's history reads (this is the eighth).
--
-- SELECT only, and only for a mutual friendship — are_friends() requires both
-- directed rows, so a half-pair grants nothing.

do $$ begin
  create policy "fact_goal_target friend access"
    on public.fact_goal_target
    for select
    to authenticated
    using (public.are_friends(auth.uid(), user_id));
exception when duplicate_object then null; end $$;
