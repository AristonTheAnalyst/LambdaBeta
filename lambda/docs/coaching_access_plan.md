# Coaching & friendship — one relationship, two consents

**Status:** proposed, nothing implemented (2026-10-28). Supersedes the
two-table coaching model built 2026-10-26 (#21–#24): `coaching_relationship`,
the invite/accept RPCs, the assignment flow, and the separate Coach roster.

## Decisions locked (2026-10-28)

1. **Friendship is request/accept.** Entering a code creates a *request*; the
   **code's owner accepts** (option A). A code alone never grants anything.
2. **Coaching is one-way and athlete-initiated.** The athlete asks a friend to
   coach them; the friend accepts. There is no mutual coaching — each
   direction is its own ask.
3. **Friends and coaching are one relationship.** The grant lives on the
   athlete's own directed `friend_relationship` row, beside `share_notes`.
4. **The coach acts on the athlete's behalf:** Session is fully usable (start,
   log, end, browse, edit records) and Library is readable **and writable**
   (create + edit). Delete is the one thing refused, everywhere.
5. **Assignments retire.** Creating directly in the athlete's library replaces
   "send a workout as a copy".
6. **Block and code rotation ship in this pass.** Blocking automatically
   rotates the blocker's friend code; a manual rotate button exists too.
7. **Coaches never delete. Anything.** No coach `DELETE` policy on any table
   (children, assignments and feedback included — the old coach-withdraw and
   delete-feedback policies are dropped), no delete affordances in coach mode,
   and an upload that tried it is refused by RLS. Coach-mode Cancel becomes
   "End session"; removals in a live session soft-flag instead of deleting.
8. **Authorship is a first-class column.** `user_id` stays "whose data this
   is"; `created_by_user_id` answers "who put this down". See the convention
   below — collaboration makes the two diverge everywhere, so the app adopts
   the rule now rather than per feature.

## What exists today (to be replaced)

| Piece | Where |
|---|---|
| Instant mutual friendship by code | `add_friend_by_code` (writes both directed rows) |
| Per-friend flags | `friend_relationship.share_notes`, `nickname` (owner's directed row) |
| Coaching consent | `coaching_relationship.accepted_date`; `coach_invite_by_code`, `accept_coaching_invitation`, `remove_coaching_relationship` |
| Coach stream | `coaching_data` gated on `coaching_relationship.accepted_date` |
| Coach UI | Profile → Coach (`/profile/coach`), roster + invitations + assignments |
| Assignment | `fact_coach_assignment` (snapshot + names, athlete accepts a copy) |
| Feedback | `fact_coach_feedback`, one row per (coach, session) — **stays** |
| Client | `FriendRepository`, `CoachRepository`, `Friend`, `CoachAssignment` |

## The model

`friend_relationship` keeps its two directed rows per friendship. New columns:

| Column | Meaning |
|---|---|
| `accepted_date` | NULL = pending request; set = the friendship exists |
| `coaching_requested_at` | The **athlete** asked this friend to coach them |
| `coaching_granted_at` | The **coach** accepted — the grant, on the athlete's row |
| *(existing)* `nickname`, `share_notes` | Unchanged, owner's row only |

A friendship exists only when **both** directed rows have `accepted_date`.
The coaching grant is on the athlete's row (`user_id` = athlete,
`friend_user_id` = coach). Removing the friendship removes the grant with it.

### States

| The athlete's row toward the coach | Meaning |
|---|---|
| pending (`accepted_date` NULL) | friend request sent; nothing flows |
| accepted, no coaching columns | friends |
| accepted + `coaching_requested_at` | athlete asked; awaiting the coach |
| accepted + `coaching_granted_at` | coach may read + create on the athlete's behalf |

## Consent flows (server)

All multi-party writes are SECURITY DEFINER RPCs; each client mirrors **its
own** row locally and the other side receives theirs through `user_data`.

| Flow | RPC | Writes |
|---|---|---|
| Request friend | `request_friend_by_code(code)` | caller's own row, `accepted_date` NULL. If the reverse pending row exists, accept both (mutual intent). Refused if blocked. |
| Accept friend | `accept_friend_request(requester)` | stamps `accepted_date` on **both** rows |
| Decline / cancel | `decline_friend_request` / own-row delete | drops the pending row |
| Unfriend | existing `remove_friend` | deletes both rows (grant goes with them) |
| Ask to be coached | own-row update | `coaching_requested_at = now()` (no RPC — the row is the athlete's) |
| Accept coaching | `accept_coaching(athlete)` | stamps `coaching_granted_at` on the **athlete's** row |
| Decline / end | `decline_coaching(athlete)` / `end_coaching(athlete)` | clears requested / granted on the athlete's row |
| Revoke | `revoke_coaching(coach)` | athlete clears their own grant (RPC, so it can also end the request) |
| Block | `block_user(target)` | inserts `user_block`, deletes both friend rows, rotates the blocker's code |
| Unblock | `unblock_user(target)` | deletes the block row |
| Rotate code | `rotate_friend_code()` | new unique code in `dim_friend_code`; returns it |

`friend_relationship` writes are column-limited: the client may update
`nickname`, `share_notes`, `coaching_requested_at`; `accepted_date` and
`coaching_granted_at` are RPC-only, so a client cannot self-accept a
friendship or self-grant coaching. (Postgres column grants + the RPCs do
this; a queued PowerSync PATCH carries only the changed columns.)

`user_block(blocker_user_id, blocked_user_id, blocked_date)` is visible only
to the blocker (`SELECT` own rows; writes via RPC). The blocked person is
never told.

## Streams

Two changes to `powersync/sync-streams.yaml`:

1. **A flags slice**, in `friends_data`: each friend's own directed row toward
   the viewer, without `nickname` —
   `SELECT user_id, friend_user_id, share_notes, coaching_requested_at,
   coaching_granted_at FROM friend_relationship WHERE user_id IN my_friends`.
   This is how the coach's device knows its grant, and how both sides render
   the friend-settings state. The nickname stays private.
2. **The coaching gate moves** from `coaching_relationship.accepted_date` to
   the athlete's row's `coaching_granted_at`, and `coaching_data` grows the
   athlete's **library**: `dim_exercise`, `dim_variation`,
   `dim_planned_session` + `_exercise` + `_set`,
   `dim_planned_session_program` (so the library can tell a standalone workout
   from a program copy), `fact_goal` + `fact_goal_target`, and (phase 4)
   `fact_program_review`. Sessions, children, notes, goals and the name slice
   are already there; sessions stay **completed-only**.

A coach who is also a friend receives overlapping rows through both streams;
PowerSync dedupes by id, so the cost is bandwidth, not corruption. If it
matters later, `friends_data` can exclude rows for athletes the friend coaches.

The athlete's device receives coach-created rows through `user_data` (they
carry the athlete's `user_id`), so no extra athlete-side stream is needed.

## RLS

- **`friend_relationship`**: own-row insert (pending only), own-row update
  (column-limited above), own-row delete. Acceptance, decline, block and
  rotation are RPC-only.
- **`user_block`**: `SELECT` where `blocker_user_id = auth.uid()`; writes via
  RPC.
- **Library reads**: replace `coaches_athlete()`/`accepted_date` with
  `is_coach_of(owner)` — an accepted friendship where the owner's row toward
  the caller has `coaching_granted_at`.
- **Coach INSERT** on the whole writable tree (sessions and children, library
  dims and children, notes, goals and targets): `is_coach_of(user_id) AND
  created_by_user_id = auth.uid()::text` (the column is text). The acting
  owner is `user_id`; the author
  is the coach. Every row the coach writes carries both, children included.
- **Coach UPDATE** on the same tables: `using (is_coach_of(user_id))` with the
  same check. A `BEFORE UPDATE` trigger (`lock_row_identity`) refuses any
  change to `user_id` or `created_by_user_id`, so a coach cannot move a row to
  another athlete or rewrite the author (a policy's WITH CHECK cannot compare
  OLD and NEW).
- **No coach DELETE, anywhere.** Enforced by the absence of a coach policy
  rather than by hiding buttons; a refused DELETE is quarantined by PowerSync
  and the row reappears, so the client must not emit the op at all.
- `fact_coach_feedback` keeps its either-side shape, gated on `is_coach_of`
  for the coach's write. Its coach DELETE policy is dropped — feedback can be
  edited, never deleted.

### Authorship convention (2026-10-28)

Two facts per row, never conflated:

- `user_id` — **whose data this is**. Ownership; what the streams and RLS key
  on.
- `created_by_user_id` — **who put it down**. Nullable; `NULL` means the
  owner wrote it (every row before collaboration, so no backfill).

Read it everywhere with one expression: `coalesce(created_by_user_id,
user_id)`. The UI only draws a mark when the two differ ("Added by your
coach").

Where the column goes — the rule, not a per-feature choice: **every row a
second person can create under a grant, plus every child row in a tree where
that can happen.** Today that is the library tree:

`fact_session`, `fact_session_exercise`, `fact_session_exercise_set`,
`dim_exercise`, `dim_variation`, `dim_planned_session`,
`dim_planned_session_exercise`, `dim_planned_session_exercise_set`,
`dim_exercise_note`, `fact_goal`, `fact_goal_target`, and (phase 4)
`fact_program_review`.

Children carry their own stamp because both people can add rows inside the
same workout or session, and "who put *this set* down" can differ row to row.

Deliberately excluded: identity/relationship rows (`dim_user`,
`dim_friend_code`, `friend_relationship`, `fact_bodyweight`,
`dim_pr_view_setting`, `fact_coach_feedback` — the latter already names its
author).

Two rules that go with it:

- **No foreign key to `dim_user`** on `created_by_user_id` (or
  `ON DELETE SET NULL` at most). A default-FK would let deleting an account
  cascade into the athlete's rows — losing content because a coach left.
- **Creation is not last-edit.** When edits become collaborative (v2),
  `updated_by_user_id` + `updated_date` arrive as a second pair, same
  null = owner rule. A row the coach created and the athlete later edited has
  two authors; one column must not answer both.

## Client

- **Models**: `Friend` gains `acceptedDate`, `coachingRequestedAt`,
  `coachingGrantedAt`; `Exercise`, `Variation` (if surfaced), `PlannedSession`,
  `Goal` gain `createdByUserId`. New `BlockedUser`.
- **`FriendRepository`**: `requestByCode` (replaces `addByCode`), accept,
  decline, cancel, unfriend, block, unblock, rotateCode,
  requestCoaching/stopCoaching (own row), and the coach-side accept/decline/end
  RPCs (or keep those in `CoachRepository`, whichever reads better).
- **`CoachRepository`**: invitations and assignments go; feedback and the
  grant actions remain.
- **Acting user**: the coach opens the athlete's surfaces with an
  `actingUserId` + display name. Reads already take `userId:` (the friend
  path); writes do not — `ExerciseRepository`, `PlannedSessionRepository` and
  `ProgramRepository` (goals) gain an explicit target user id on creates,
  defaulting to the signed-in user. Every coach-created row also writes
  `created_by_user_id = signed-in user`.
- **UI**
  - Friends tab: the code card gains **Rotate**; adding by code reads
    "Request sent"; new **Requests** section (incoming Accept/Decline, outgoing
    Cancel); **Blocked** section; friend settings gains **Ask to coach me** /
    coaching status / **Stop coaching**.
  - Coaching folds into Friends: a **Coaching** section lists athletes who
    granted you coaching, plus incoming coaching asks (Accept/Decline).
    Profile → Coach either disappears or becomes a shortcut to that section.
  - Coach mode: opening an athlete's Session tab reuses `LogsScreen` and the
    session viewer (`userId:` + `readOnly:` today); opening their Library
    reuses the library hub, workout editor and goals screen with `actingFor:`.
    A fixed banner reads "Natasha's library — you're creating as her coach",
    with a way back.
  - Athlete side: a coach-created exercise/variation/workout/goal wears an
    **Added by your coach** mark (`created_by_user_id != user_id`).
- **Retired**: the Coach screen's invite/roster/assign verbs and the whole
  assignment sheet. `fact_coach_assignment` and `coaching_relationship` stay as
  dormant tables until a held drop migration (the programs precedent).

## Migration order

1. **`20261028140000_friend_requests.sql` (additive, safe)**
   - `friend_relationship`: add `accepted_date`, `coaching_requested_at`,
     `coaching_granted_at`; backfill `accepted_date = created_date` on every
     existing row (today all friendships are accepted).
   - create `user_block`; add `created_by_user_id` to the eight library tables
     named in the authorship convention.
   - create the RPCs and `is_coach_of`.
   - migrate `coaching_relationship`: for each accepted pair, ensure both
     friend rows exist with `accepted_date`, then stamp
     `coaching_requested_at`/`coaching_granted_at` on the athlete's row.
     Pending invitations become `coaching_requested_at` (or are dropped).
   - add coach INSERT policies; switch the read helpers to `is_coach_of`.
2. **Client schema**: new columns on `friend_relationship`, the dims and
   `fact_goal`; `user_block` table + `_pkColumns`; new models.
3. **Stream deploy (user)**: the flags slice + the new `coaching_data` gate and
   library queries. Must follow (1) and precede (4).
4. **Build**: requests, block/rotate, coaching ask/accept, coach mode read.
5. **Held migration**: drop `coaching_relationship` (after the stream deploy
   and a build that no longer reads it). `fact_coach_assignment` stays dormant.

## Phases

| Phase | Ships | Verifiable on device |
|---|---|---|
| 0 | Additive schema + client schema + helpers | app unchanged, sync green |
| 1 | Friend requests, block, rotate code | request → owner accepts; blocked code fails |
| 2 | Coaching ask/accept, retire invitations; stream gate on the flag | coach sees the athlete's sessions/notes as today |
| 3 | On-behalf **read** of the athlete's library | coach browses her exercises/workouts/goals |
| 4 | On-behalf **create** + provenance marks | coach creates an exercise/workout in her library; she sees "Added by your coach" |
| 5 | Assignment flow retired; held drop; docs | old screens gone, feedback still works |

## Testing

**Two real accounts** is the end state. For the Natasha test, seeding is the
only route because her account is not at hand. The current-build edge was
seeded on 2026-10-28 (coach = the project owner's account, athlete = the
Natasha test account, `accepted_date = now()`); her device was not touched.
The SQL below is the pattern, with ids left out on purpose:

```sql
-- Resolve both ids from the two friend codes (ask Rocky for both codes).
select user_id, friend_code from public.dim_friend_code
 where friend_code in ('<your-code>', '<natasha-code>');

-- Current build (before this plan ships): an accepted coaching edge.
insert into public.coaching_relationship (coach_user_id, athlete_user_id, accepted_date)
values ('<your-id>', '<natasha-id>', now())
on conflict (coach_user_id, athlete_user_id)
do update set accepted_date = excluded.accepted_date;

-- After this plan ships: friendship + the athlete's grant.
-- (both directed rows accepted, then:)
update public.friend_relationship
   set coaching_requested_at = now(), coaching_granted_at = now()
 where user_id = '<natasha-id>' and friend_user_id = '<your-id>';
```

The coach's device syncs the relationship via `user_data` and her data via
`coaching_data`; nothing on her device needs to change. This writes to the
real project — confirm the account is the test one before running it.

## Checks per phase

- Friend request: B enters A's code → A sees a request and accepts → both see
  each other; a blocked code returns `friend_code_not_found`/blocked.
- Block: A blocks B → both friendship rows gone, A's code changes, B's old
  code fails, B cannot re-request; A can unblock.
- Coaching: athlete asks → coach accepts → coach reads sessions + notes;
  coach declines → nothing; athlete revokes → coach loses access on the next
  sync round.
- Create on behalf: coach creates an exercise/variation/workout/goal in her
  library; it lands on her device with `created_by_user_id = coach`; she sees
  the "Added by your coach" mark; the coach cannot edit or delete it.
- Feedback: still one row per (coach, session), readable by both.
- Upload: every coach-created row passes RLS on upload (watch
  `upload_failures`).

## Risks & open questions

- **Cross-user write authority is the sharp edge.** Create-only, RPC-less
  inserts checked by `is_coach_of`, and `created_by` are the rails. Any future
  edit/delete for coaches needs its own consent design.
- **Stream size**: the coach now receives an athlete's library, not just their
  history. For a long-running athlete this is a real download; consider
  streaming only the last N or lazy-loading library writes later.
- **Column grants vs PowerSync PATCHes**: verify the queued PATCH shape against
  Postgres column privileges early — this is the piece most likely to surprise.
- **Code rotation UX**: a rotated code must be re-shared; the UI should show
  the new code and copy it immediately.
- **Coach-created rows outlive the grant** (they are the athlete's). Deleting
  them when coaching ends would destroy her data; they stay.
- **Open**: can the coach create a review pass for her? Not in v1.
- **Decided (2026-10-28)**: the coach **can** start, log and end a session for
  her — full Session use, with no delete anywhere. Active sessions are not
  streamed, so a coach-started session is invisible to the athlete until it
  ends, and the coach cannot see one the athlete started on her own device.
- **Open**: the athlete's Library while the coach is acting shows the same
  screens; whether the coach's session view should also mark her own notes is
  a copy decision for phase 3.
