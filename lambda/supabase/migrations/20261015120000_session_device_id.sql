-- Which device created the session (2026-10-15). A locally-generated uuid,
-- kept per install; the app uses it to tell its OWN live session apart from
-- one started on another device, so a second device can never silently
-- adopt (or write into) a session it did not start. Rows written before this
-- migration — and by clients that predate it — stay NULL, which the app
-- reads as "another device": the safe reading, since it only ever prompts.
-- Additive only; RLS is whole-row and the sync streams are SELECT *, so
-- nothing else changes.
alter table public.fact_session add column device_id text;
