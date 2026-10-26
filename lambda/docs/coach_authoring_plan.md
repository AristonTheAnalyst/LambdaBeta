# Coaching — authoring, assignment and feedback (backlog #24)

The plan #24 asks for ("split into its own plan when reached"). Written
2026-10-26, the same day #21 (read-only) and #22 (invite/accept) shipped.

## What already exists

- `coaching_relationship` (coach, athlete, created_date, accepted_date) with
  the consent gate: nothing about an unaccepted athlete leaves their account.
- `coaching_data` stream: an accepted athlete's completed sessions, children,
  dims, goals and a name-only `dim_user` slice — the coach reads through the
  same viewer the Friends tab uses (`/profile/coach/:athleteId` →
  `/coach/:athleteId/sessions/:sessionId`).
- Writes are RPC-first and mirror locally (`CoachRepository`); the coach's own
  relationship rows ride `user_data`.

## What #24 adds

The write direction: the coach authors a workout, assigns it to an accepted
athlete, and leaves feedback on the athlete's sessions. The athlete accepts
each assignment; accepted content becomes THEIR row.

### 1. Assignment is a snapshot, never a shared row

`fact_coach_assignment` carries a `ProgramContent` document (the review
snapshot's own shape, built by `ProgramHistoryRepository.buildContentForSessions`
over one session) plus a name map. Why:

- Templates stay the coach's rows; the athlete's accept materializes a copy
  into their own library, so neither side's later edits collide.
- The stream carries the assignment row, never the coach's template rows.
  The athlete's device needs no coach-side reads at all.
- The document is write-once — the same argument `ProgramContent` already
  makes for reviews.

**Names must be embedded** — the one deviation from the "names are not
embedded" rule, because that rule assumes both sides share the same
per-user `dim_exercise`/`dim_variation` rows, and they do not. The
assignment's `names_json` maps the snapshot's exercise/variation ids to the
names the coach saw; the athlete's accept resolves each name against their
own library (`findExerciseByName` / `findVariationByName`, case-insensitive),
creating or reactivating what is missing. An id the coach could not resolve
(a deleted exercise) has no name and the copied group is skipped.

### 2. Feedback is a coach-authored row on the athlete's session

`fact_coach_feedback`: one row per (coach, session), body text, edited_date.
Both parties read it; only its author writes it, only while the relationship
is accepted and the session belongs to the athlete. The session viewer draws
it as a card for either side; the write affordance exists only on the coach's
route. RLS is row-level, so the athlete *could* rewrite a row they were sent —
the same trust level as the friend nickname, and the app never offers it.

### 3. Consent is per assignment

The coach's insert is a normal local-first write (no RPC): the row is the
coach's own, RLS checks `coaches_athlete()` and an unaccepted stamp. The
athlete's accept is a single local transaction — copy the document (fresh
ids, remapped dims), stamp `accepted_date` and `athlete_planned_session_id`
— and their decline a stamp. A pending assignment is invisible to the
athlete's library; a declined one stays as history but grants nothing.

### 4. Where it lives

Everything stays on the Coach screen (one page, both sides):

- **Coach**: swipe an athlete row → assignment glyph → assign sheet (the
  coach's active workouts, newest first, one selected at a time; a workout
  already pending to that athlete is not marked — it would need a per-pair
  read the sheet does not do) → optional note → **Send workout**. No subtitle
  count on the row: the status lives in the section below instead.
- **Athlete**: **ASSIGNMENTS TO YOU** above ATHLETES — `name · From <coach> ·
  date`, the note, Accept / Decline. Accepted rows leave the section (their
  copy now lives in the Library).
- **Both (coach side)**: **ASSIGNMENTS SENT** after INVITATIONS SENT —
  `name · To <athlete> · AWAITING REPLY / ACCEPTED`, swipe to withdraw while
  pending, tap to open the athlete.
- **Feedback**: on the coach's session viewer, a feedback card with a
  Leave / Edit feedback word button; on the athlete's own record the same
  card, read-only. One row per coach; each row draws its author (resolved
  through `CoachRepository.userNames`, with `Coach` as the fallback), its
  date (`· EDITED` when rewritten) and its prose. The sheet is a multiline
  `LambdaInput` with Save gated on a non-empty, changed body, and Delete
  behind the house two-verb confirm. Both sheets stay open on a refusal and
  draw the ViewModel's own sentence (under the field / above Send), so a
  failed write never pops a sheet as if it had landed.

### 5. Attribution

`dim_planned_session.coach_assignment_id` (plain ref, the `base_session_id`
precedent). The assignment card names the coach (their name arrives through
the existing `my_coaches` slice); the plan itself keeps who authored it.

## Server — `20261026170000_coach_authoring.sql`

- `dim_planned_session.coach_assignment_id text`.
- `fact_coach_assignment(assignment_id text pk, coach_user_id uuid,
  athlete_user_id uuid, planned_session_id text, name text, note text,
  snapshot_content text not null, names_json text, created_date timestamptz,
  accepted_date timestamptz, declined_date timestamptz,
  athlete_planned_session_id text)` + athlete/coach indexes.
- `fact_coach_feedback(feedback_id text pk, coach_user_id uuid,
  athlete_user_id uuid, session_id text, body text, created_date timestamptz,
  edited_date timestamptz)` + unique (coach_user_id, session_id).
- `coaches_athlete(coach, athlete)` SECURITY DEFINER helper (accepted rows).
- RLS:
  - assignment SELECT either side; coach INSERT own + `coaches_athlete` +
    unstamped; athlete UPDATE own (accept/decline); coach DELETE own only
    while unaccepted.
  - feedback SELECT either side; coach INSERT/UPDATE/DELETE own +
    `coaches_athlete` + the session is the athlete's.
- Publication: both tables.

## Client

- `schema.dart`: two tables, one new column.
- `database.dart` `_pkColumns`: the two ids.
- Models: `CoachAssignment`, `CoachFeedback`; `PlannedSession.coachAssignmentId`.
- `CoachRepository`: `watchAssignments`, `assign`, `acceptAssignment`,
  `declineAssignment`, `withdrawAssignment`, `watchFeedback(sessionId)`,
  `saveFeedback`, `deleteFeedback`. The accept path needs the exercise and
  planned-session repositories (injected for host tests).
- `CoachViewModel`: assignment lists in state, the five commands.
- `SessionDetailViewModel`: feedback subscription + save/delete; the screen
  gains `canCoach` (coach route only) and draws the feedback card.
- Streams (`user_data`): the assignment and feedback queries with
  `coach_user_id = auth.user_id() OR athlete_user_id = auth.user_id()` —
  the relationship row's own shape. Deploy is the user's dashboard step.

## Out of scope (documented)

- Program-level assignment (program/run surfaces are retired from the UI; the
  workout is the unit the app plans and starts).
- Coach edits to the athlete's existing rows — content is copied, never
  mutated.
- Notifications, feedback threads, multiple coaches' feedback shown together
  (the card lists rows; v1 writes one per coach).

## Verify

- Host tests: model round-trip; the accept remap (fake exercise repo —
  name resolution, missing-exercise creation, archived reactivation; fresh
  ids; stamped assignment); feedback commands; Coach-screen widget tests for
  the assign sheet and the athlete's Accept/Decline.
- `flutter analyze lib test`; full `flutter test test/`.
- `supabase db push` before any build writes the new columns.
- Two accounts after the stream deploy: assign → athlete accepts → copy in
  their library; feedback shows on both sides; a declined assignment leaves
  no copy; a removed coach's assignment no longer uploads (RLS guard).
