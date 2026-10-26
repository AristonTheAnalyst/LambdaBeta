---
name: sync-contract
description: >
  Add, modify, or verify a table's PowerSync/Supabase sync wiring in this app.
  Use when a table is created or changed, when schema.dart / database.dart /
  sync config are edited, or when data silently does not sync (empty on device,
  rows vanish after upload, uploads fail).
---

# PowerSync three-way sync contract (lambda)

Every table that a client reads or writes must be registered in **exactly
three places** to sync. If one is missed, PowerSync silently drops the data —
no error, no log, rows just vanish after an upload (or never arrive). This is
the root cause class behind the "lessons only show one / data disappears"
incidents.

## The three places

1. **Client schema** — `lib/core/powersync/schema.dart`
   A `Table('name', [Column...])` entry. Columns here are the exact columns the
   local PowerSync SQLite view exposes and that the repo INSERTs/UPDATEs/SELECTs.
2. **Upload PK map** — `lib/core/powersync/database.dart`
   - `_pkColumns`: single-column-PK tables → real PK column name
     (`'fact_lesson': 'lesson_id'`).
   - `_compositeKeyTables`: tables whose Postgres PK is a composite pair and
     that have **no server-side `id` column** → list of the pair's columns.
   This is what the `uploadData` PUT/PATCH/DELETE path uses to address rows on
   Supabase.
3. **Sync service config** — NOT in this repo.
   The PowerSync Cloud (journeyapps.com) Dashboard → project/instance → **Sync
   Streams** (or legacy Sync Rules). The deployed YAML decides what streams
   DOWN to each client. Adding a table to the Postgres publication alone is
   NOT enough — the stream/rule must also be deployed. The user edits this
   manually; the assistant can only prepare the YAML for them.

## The one shared invariant

**PowerSync requires every synced table to expose a primary-key column named
`id` (text) on the client.** In stream/rule queries this is done with an alias,
e.g. `SELECT *, lesson_id as id FROM fact_lesson`. The repo INSERT always
writes a uuid into both the internal `id` and the real PK column. Table PK
columns (schema v2, from migrations):
`dim_user→user_id`, `dim_exercise→custom_exercise_id`,
`dim_variation→custom_variation_id`,
`fact_bodyweight→user_weight_id`, `dim_program→program_id`,
`fact_program_run→program_run_id`, `dim_lesson→lesson_id`,
`fact_session→session_id`, `fact_session_exercise→session_exercise_id`,
`fact_session_exercise_set→session_exercise_set_id`,
`dim_planned_session→session_id`,
`dim_planned_session_exercise→planned_exercise_id`,
`dim_planned_session_exercise_set→planned_set_id`,
`dim_planned_session_program→planned_session_program_id`,
`fact_goal→goal_id`,
`fact_goal_target→goal_target_id`,
`dim_pr_view_setting→pr_view_setting_id`,
`dim_friend_code→user_id`,
`coaching_relationship→(coach_user_id,athlete_user_id)` and
`friend_relationship→(user_id,friend_user_id)` (composite — the two tables
with no server-side `id`).

## The friends stream: the query is the privacy boundary (2026-10-23)

There are now **three** auto-subscribed streams. `user_data` carries the
user's own rows; `friends_data` (in `powersync/sync-streams.yaml`) carries
each mutual friend's history; `coaching_data` (2026-10-26) carries an
accepted athlete's history to their coach. Streams bypass RLS, so that YAML's
queries — not the policies — decide what a device may hold.

- **Mutual by construction.** A `with:` CTE `my_friends` selects
  `friend_relationship` rows where `user_id = auth.user_id()` **and** the
  reverse row exists. Friendship is two directed rows; a one-way row matches
  nothing.
- **Completed records only.** `fact_session` is filtered
  `end_datetime IS NOT NULL` — a friend's live session is never sent. The
  child tables filter on `user_id IN my_friends`, not on session id: that is
  one bucket per friend instead of one per session (thousands for a long
  history). A mid-session friend's child rows can therefore download
  parentless; no surface can name or open them because the parent row is
  withheld.
- **Names and the code fallback.** The friend's `dim_user` slice selects
  `user_id, user_name, user_lastname` — never height, weight, gender, DOB or
  profile. A SECOND `dim_friend_code` query (`WHERE user_id IN my_friends`)
  streams each mutual friend's code (2026-10-25): the Friends list falls back
  to it when a friend has no name and no nickname. The owner's own code keeps
  its own query, `WHERE user_id = auth.user_id()`.
- **Nicknames are the owner's own.** `friend_relationship.nickname` rides
  `SELECT *` on the caller's own directed rows only (the query above), so a
  label never reaches the friend it names. It is the repository's one
  local-first write — the composite-key patch below carries it, no RPC.

## The coaching stream: consent is the gate (2026-10-26)

`coaching_data` is `friends_data`'s shape with one difference that matters:
its `with:` CTE `my_athletes` requires `coaching_relationship.accepted_date`
(added by `20261026140000_coaching_consent.sql`). An invitation the athlete
has not accepted matches nothing, so **no athlete row — not even a name —
reaches the coach's device**. Push the migration before deploying this
stream; the `accepted_date` column must exist or the CTE fails to parse.

- What it sends: the athlete's name-only `dim_user` slice, completed
  `fact_session` rows (`end_datetime IS NOT NULL`), their exercise/set
  children keyed on `user_id IN my_athletes` (one bucket per athlete, never
  per session), `dim_exercise` / `dim_variation` / `dim_lesson`,
  `fact_goal` and `fact_goal_target`. Body metrics and the profile stay
  private, exactly as on the friends path.
- What it does NOT send: `fact_bodyweight`, `dim_program`, planned sessions
  — the record viewer reads names off the session's own snapshot.
- The coach's own `coaching_relationship` rows ride `user_data` (own rows,
  `SELECT *`), so the roster's local read sees the edge and its
  `accepted_date`; the athlete's name still arrives only through
  `coaching_data`. The app has no coach-side write in #21 — invite, accept
  and revoke are #22's, and `coaching_relationship`'s `ps_crud` purge was
  removed with the stream so a future write uploads normally.

**The own-row-only mirror rule.** `FriendRepository.addByCode` calls the
SECURITY DEFINER RPC and then mirrors ONLY the caller's own directed row,
under the synthetic id `'<userId>-<friendId>'` (the stream synthesizes the
same id). Never mirror the reciprocal row and never a friend's `dim_user`
row: those are writes the caller's RLS rejects, and 42501 is fatal — the op
is quarantined in `upload_failures` and the write silently never lands.
`friend_relationship` is in `_compositeKeyTables`, so the uploader upserts on
the pair; the mirror's PUT after the RPC is a no-op against the row the RPC
already wrote. A removal's queued DELETE is harmless: the local own row is
deleted first, so the uploader finds no pair and skips the op.

## Migration history hygiene

**Never hand-apply a migration under a version you invented.** `supabase db
push` does not diff the schema — it compares the version prefix of each local
filename against `supabase_migrations.schema_migrations.version`. A file
renumbered to `20260814000000_my_change.sql` when the cloud recorded it as
`20260813043831` looks *unapplied*, so the next `db push` re-runs it. Postgres
has no `ADD CONSTRAINT IF NOT EXISTS`, so migrations using bare `ADD CONSTRAINT`
fail partway and leave the database half-migrated. Use the real applied version,
not a placeholder.

### Checking for drift

`schema_migrations` is the authority — compare it against the directory:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```

`supabase migration list --linked` does this for you, but the CLI needs
`supabase login` first: `supabase/.temp/pooler-url` stores no password, so it
cannot connect on its own.

### Reconciling a drifted history

- **Same migration, different version** → rename the local file to the cloud
  version.
- **Applied on the cloud, no local file** → backfill from the stored SQL:
  `select statements[1] from supabase_migrations.schema_migrations where
  version = '...'` is the exact SQL that ran.
- **Local file, no cloud row** → never applied. Delete it, unless a later
  migration folded in its intent.

### Comparing content (the part that bites)

`statements` is a `text[]` whose shape is **not consistent**: sometimes one
element holding the whole file verbatim (comments and semicolons included),
sometimes one element per statement with the trailing `;` stripped. So
comparing `statements[1]` against a whole file reports false differences, and
re-joining the array with `;` breaks the single-element case. Both mistakes
produce confident wrong answers — 2026-09-30 concluded "22 files drifted" that
way, when in fact 49 of 51 matched.

Normalize the ambiguity away — strip `--` comments, whitespace, **and
semicolons** — then hash both sides:

```sql
md5(lower(regexp_replace(regexp_replace(regexp_replace(
  array_to_string(statements, chr(10)), '--[^\n]*', '', 'g'),
  '[[:space:]]', '', 'g'), ';', '', 'g')))
```

Locally: `perl -pe 's/--.*$//' f.sql | tr -d '[:space:];' | tr '[:upper:]'
'[:lower:]' | md5 -q`. Matching hashes prove the local file is the migration
that actually ran. A file that differs *on purpose* (an added `if exists`
guard, say) should say so in a comment — otherwise the next person "fixes" it.

### Held migrations (a destructive half that must land later)

`supabase db push` has no per-file flag — it applies every pending file in
`supabase/migrations/`. So when a change must land in two moments (additive
first, destructive after the sync-stream deploy and the app build), the
destructive file is **held** in `supabase/held_migrations/`, which `db push`
never reads. A plain push is then safe by construction, instead of resting on
someone remembering to move a file out and back.

Held files keep their real version (nothing was ever applied under it, so
there is no drift to reconcile) and the directory's README carries the landing
instructions. First case: `20261005130100_drop_program_revisions.sql`
(reviews replace versions, 2026-10-05).

## Deleting rows: the client has no constraints

PowerSync's local SQLite is built from `schema.dart` and declares **no foreign
keys and no checks**. Every rule the cloud schema enforces is absent on the
client, which matters in both directions:

- **`ON DELETE CASCADE` / `ON DELETE SET NULL` never fire locally.** A
  client-side delete has to mirror them by hand, or the local rows stay wrong
  until a sync round-trip — which never comes if the device is offline, and the
  UI reads local rows. This is a real bug that shipped into a branch: deleting
  `dim_program` locally left `fact_session.program_run_id` pointing at a run
  that no longer existed, because the `SET NULL` is the *server's* rule. The
  integration test caught it; nothing else would have.
- **A local integration test cannot prove statement order.** Nothing refuses a
  bad order locally, so a green test says only that the statements ran. The
  order those deletes need (reviews before runs, runs before blocks) exists to
  satisfy NO ACTION edges that live only in Postgres. Prove it separately
  against the real constraints — seed the fixtures and run the statements in a
  transaction you `rollback`, e.g. through the Supabase MCP tool.

The reverse also bites: the server has CHECKs the client lacks, so a row the
client stores happily can be rejected on upload. `fact_goal_block_scope_check`
(`block_id` implies `program_id`) is one — the local DB will hold a row the
server refuses.

## Workflow to add or change a table

1. **Migration** — `supabase/migrations/<ts>_<name>.sql`:
   - Create/alter the table with the real PK (text) and all needed columns.
   - Add the table to the publication if it should sync:
     `alter publication powersync add table public.<name>;`
   - Add RLS policies + grants so the app's owner row is readable/writable.
2. **Client schema** — add the matching `Table(...)` in `schema.dart` with the
   exact columns (text for arrays/integers that arrive as JSON/text).
3. **Upload map** — register in `database.dart`: `_pkColumns` (single PK) or
   `_compositeKeyTables` (composite pair, no server id).
4. **Repository** — a repo in `lib/data/repositories/` with create/read/
   update/delete that INSERTs `id` + PK and filters by `user_id`.
5. **Sync config (user step)** — hand the user the exact stream/rule YAML
   (with `SELECT *, <pk> as id ...` aliasing) to paste into the PowerSync
   Dashboard → Validate → Deploy.
6. **Verify locally** before and after the user deploys:
   - `flutter analyze lib/` clean.
   - On-device/integration test exercising the real repo + real PowerSync DB
     (real triggers) — host `flutter test` cannot load the native dylib, so use
     `flutter test integration_test/... -d <device>`.
   - Confirm the table appears in the local DB and rows survive an upload
     round-trip (create → force sync → still present).

## Diagnosing "data silently missing / vanishes on device"

Follow this order:

1. **Remote truth** — `supabase db query --linked "SELECT * FROM public.<name>
   WHERE user_id='...'"` (run from `supabase/`). Rows there = uploads worked.
2. **Local truth** — read the simulator's app DB:
   `xcrun simctl get_app_container booted <bundleid> data`, then sqlite3 the
   `lambda.db` in `Library/Application Support/`. Check `ps_data__<name>` and
   the view. Empty local + full remote = sync-down gap (stream missing).
3. **Upload queue** — `SELECT id, substr(data,1,300) FROM ps_crud` (data is
   JSON; empty = nothing pending, all uploaded).
4. **Remote schema/indexes** — `supabase db query --linked` for unique
   constraints the migrations didn't create (a stray unique index explains
   silent second-insert failures).
5. **Stream config** — confirm the table is in the deployed Sync Streams/Rules
   (user checks the Dashboard; assistant can only prepare YAML).

## When to use which test target

- **Unit/widget** (`test/`) — pure logic + fakes (`implements` the repo, NOT
  `extends` — extending evaluates the global `ps.db`). Fine for UI/modal logic.
- **Integration** (`integration_test/`) — real repo + real PowerSync DB. This
  is the ONLY way to validate real triggers/schema on-device. Plain `flutter
  test` and `flutter test -d macos` fail with the missing `libpowersync.dylib`.
