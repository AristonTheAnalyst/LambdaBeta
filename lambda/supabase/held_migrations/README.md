# Held migrations

Migrations that must **not** be in `supabase/migrations/` yet, because
`supabase db push` would apply them alongside everything else.

## Why a directory

`supabase db push` has no per-file flag — it applies every pending file in
`supabase/migrations/`. The reviews rework splits into two halves that must
land at different moments:

1. `20261005130000_review_scope_and_snapshot.sql` — additive, safe with old and
   new clients. Stays pushable.
2. `20261005130100_drop_program_revisions.sql` — destructive. Must land **last**
   (after the sync-stream YAML is live and after every device is on the build
   that stopped writing `revision_id`). Held here.

Leaving the destructive file in the migrations directory makes the safe push
impossible to perform by accident — and getting it wrong strands devices
(`_fatalCodes` does not treat `PGRST204` as fatal, so a write against the
dropped column retries forever and stalls that device's checkpoint). Removing
the file from that directory is the fix.

## Holding `20261005130100_drop_program_revisions.sql`

**It lands after:**

1. `20261005130000` has been pushed and the cloud is at that version.
2. `powersync/sync-streams.yaml` has been deployed in the PowerSync Dashboard —
   a stream naming a dropped table fails validation and can take the whole
   stream down with it.
3. The app build that stops touching `fact_program_revision` has shipped.

**To land it:** move it back and push.

```sh
mv supabase/held_migrations/20261005130100_drop_program_revisions.sql \
   supabase/migrations/
supabase db push
```

If newer migrations have been pushed by then, the CLI may skip this file as
out-of-order (it applies only versions above the newest recorded one by
default). Either re-run with `--include-all`, or rename it to the current
timestamp — renaming is safe here specifically because the file has **never
been applied anywhere**, so there is no cloud version to drift from. (The
never-rename rule in the `sync-contract` skill is about files that already ran
under a different version.)

Do not edit the file's contents while landing it — the version in this
directory is the one that was reviewed.
