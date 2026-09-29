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
`coaching_relationship→(coach_user_id,athlete_user_id)` (composite — the
only table with no server-side `id`).

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
