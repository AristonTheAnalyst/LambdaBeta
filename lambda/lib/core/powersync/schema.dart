import 'package:powersync/powersync.dart';

const schema = Schema([
  // Local-only quarantine for uploads that failed fatally (RLS / FK / type).
  // NOT in powersync/sync-streams.yaml — failures must stay on-device so a
  // single bad row can't be silently dropped without any trace.
  Table('upload_failures', [
    // `id` is auto-added by PowerSync (every table gets one); these are the
    // additional local-only columns.
    Column.text('table_name'),
    Column.text('op_id'),
    Column.text('op_type'),
    Column.text('op_data'),
    Column.text('error_code'),
    Column.text('created_at'),
  ]),
  Table('dim_user', [
    Column.text('user_id'),
    Column.text('user_name'),
    Column.text('user_lastname'),
    Column.text('user_date_created'),
    Column.text('user_date_of_birth'),
    Column.text('user_gender'),
    Column.text('user_height_cm'),
    Column.integer('onboarded'),
    Column.text('user_weight_kg'),
  ]),
  Table(
    'fact_session',
    [
      Column.text('session_id'),
      Column.text('user_id'),
      Column.text('pre_notes'),
      Column.text('post_notes'),
      Column.text('created_datetime'),
      Column.text('end_datetime'),
      Column.text('planned_session_id'),
      Column.text('planned_session_name'),
      Column.text('program_run_id'),
      Column.integer('post_feeling'),
      Column.integer('pre_feeling'),
      // Which device created the session (2026-10-15) — the app's own live
      // session is the one carrying ITS device id; anything else active is
      // another device's, which the app only ever offers to switch to.
      // NULL (rows from before the column, or old clients) reads as "another
      // device" — the safe reading.
      Column.text('device_id'),
    ],
    indexes: [
      Index('user_end_idx', [
        IndexedColumn.ascending('user_id'),
        IndexedColumn.ascending('end_datetime'),
      ]),
    ],
  ),
  Table(
    'dim_exercise',
    [
      Column.text('custom_exercise_id'),
      Column.text('user_id'),
      Column.text('exercise_name'),
      Column.text('date_archived'),
    ],
    indexes: [
      Index('user_idx', [IndexedColumn.ascending('user_id')]),
    ],
  ),
  Table(
    'dim_variation',
    [
      Column.text('custom_variation_id'),
      Column.text('user_id'),
      Column.text('variation_name'),
      Column.text('date_archived'),
    ],
    indexes: [
      Index('user_idx', [IndexedColumn.ascending('user_id')]),
    ],
  ),
  Table('fact_bodyweight', [
    Column.text('user_weight_id'),
    Column.text('user_id'),
    Column.text('user_weight'),
    Column.text('user_weight_date'),
    Column.text('created_date'),
  ]),
  Table(
    'fact_session_exercise',
    [
      Column.text('session_exercise_id'),
      Column.text('session_id'),
      Column.text('user_id'),
      Column.text('custom_exercise_id'),
      Column.integer('exercise_order'),
      Column.text('planned_exercise_id'),
    ],
    indexes: [
      Index('session_idx', [IndexedColumn.ascending('session_id')]),
    ],
  ),
  Table(
    'fact_session_exercise_set',
    [
      Column.text('session_exercise_set_id'),
      Column.text('session_exercise_id'),
      Column.text('user_id'),
      Column.text('custom_variation_id'),
      Column.integer('set_number'),
      Column.text('weight'),
      Column.text('reps'),
      Column.text('notes'),
      Column.text('planned_set_id'),
      // Soft-delete for planned rows (2026-10-13) — deleting a planned set
      // flags it instead of removing it, so the exercise can be restored and
      // wear the minus mark. Flagged rows SURVIVE endSession (the prune keeps
      // them) and their exercise row with them, so a past session can show
      // what was deleted and offer a restore; only the derived timeline and
      // the logs list filter them out (2026-10-14).
      Column.integer('is_deleted'),
    ],
    indexes: [
      Index('se_idx', [IndexedColumn.ascending('session_exercise_id')]),
    ],
  ),
  Table(
    'dim_program',
    [
      Column.text('program_id'),
      Column.text('user_id'),
      Column.text('program_name'),
      Column.text('program_description'),
      Column.text('date_archived'),
      Column.text('program_created_date'),
      Column.text('program_updated_date'),
      // The program's shape, fixed at creation: 1 = made of blocks, 0 = a list
      // of workouts. Stored, not inferred — a blocked program with no blocks yet
      // is a real state and must not read as a simple one.
      Column.integer('uses_blocks'),
      // A simple program's remembered length; NULL = none set yet.
      Column.integer('default_target_sessions'),
    ],
    indexes: [
      Index('user_archived_idx', [
        IndexedColumn.ascending('user_id'),
        IndexedColumn.ascending('date_archived'),
      ]),
    ],
  ),
  Table(
    'fact_program_run',
    [
      Column.text('program_run_id'),
      Column.text('program_id'),
      Column.text('user_id'),
      Column.integer('target_sessions'),
      Column.integer('target_weeks'),
      Column.text('end_date'),
      Column.text('started_date'),
      Column.text('ended_date'),
      Column.integer('is_current'),
      Column.text('progression_mode'),
      // The block being followed; NULL = a blockless run. Every run before this
      // column existed is NULL, so blockless rendering is byte-identical.
      Column.text('block_id'),
    ],
    indexes: [
      Index('user_current_idx', [
        IndexedColumn.ascending('user_id'),
        IndexedColumn.ascending('is_current'),
      ]),
    ],
  ),
  // An ordered, duration-bounded phase of a program, holding workouts and (from
  // the goals phase) goals. A program either uses blocks or doesn't — never
  // mixed. `date_archived` rather than `is_archived` because a block is named,
  // dated and user-visible with its own run/review trail to keep browsable.
  Table(
    'dim_program_block',
    [
      Column.text('block_id'),
      Column.text('user_id'),
      Column.text('program_id'),
      Column.text('name'),
      Column.text('notes'),
      Column.integer('block_order'),
      Column.integer('target_weeks'),
      Column.integer('target_days'),
      Column.integer('target_sessions'),
      Column.text('start_date'),
      Column.text('end_date'),
      Column.text('date_archived'),
      Column.text('created_date'),
      Column.text('updated_date'),
    ],
    indexes: [
      Index('program_order_idx', [
        IndexedColumn.ascending('program_id'),
        IndexedColumn.ascending('block_order'),
      ]),
    ],
  ),
  // The checkpoints a program's run passes through — one row per review, per
  // proposed change, and per run close — AND the snapshot each one cut.
  // `completed_date` NULL is what makes a review open; there is no status column
  // to keep in sync with it. `snapshot_content` is the same `ProgramContent`
  // document the retired revision table held, written when the review completes.
  //
  // SCOPE — a review is a pass over a SET of workouts: `session_ids_json` is
  // the ordered planned-session ids it covers, and `reviewed_sessions_json`
  // records the ones marked done inside the pass. Both stay null on rows
  // written before reviews were re-scoped — those resolved from their legacy
  // `block_id`/`session_id` (never both set; the server checks it) — and new
  // rows leave the legacy ids null.
  Table(
    'fact_program_review',
    [
      Column.text('review_id'),
      Column.text('user_id'),
      Column.text('program_id'),
      Column.text('block_id'),
      Column.text('session_id'),
      Column.text('program_run_id'),
      Column.text('kind'),
      Column.text('title'),
      Column.text('notes'),
      Column.text('scheduled_for'),
      Column.text('completed_date'),
      Column.text('outcome'),
      Column.text('proposed_content'),
      Column.text('proposed_hash'),
      Column.text('snapshot_content'),
      Column.text('snapshot_hash'),
      Column.text('baseline_content'),
      Column.text('baseline_hash'),
      Column.text('exercise_notes_json'),
      Column.text('achievements_json'),
      Column.text('session_ids_json'),
      Column.text('reviewed_sessions_json'),
      Column.text('goal_ids_json'),
      Column.text('workout_notes_json'),
      Column.text('created_date'),
    ],
    indexes: [
      Index('user_completed_idx', [
        IndexedColumn.ascending('user_id'),
        IndexedColumn.ascending('completed_date'),
      ]),
    ],
  ),
  Table(
    'dim_lesson',
    [
      Column.text('lesson_id'),
      Column.text('user_id'),
      Column.text('custom_exercise_id'),
      Column.text('lesson_text'),
      Column.integer('pinned'),
      Column.integer('is_archived'),
      Column.text('lesson_created_date'),
      Column.text('session_id'),
    ],
    indexes: [
      Index('user_ex_idx', [
        IndexedColumn.ascending('user_id'),
        IndexedColumn.ascending('custom_exercise_id'),
      ]),
    ],
  ),
  Table('coaching_relationship', [
    Column.text('coach_user_id'),
    Column.text('athlete_user_id'),
    Column.text('created_date'),
  ]),
  // Friends (2026-10-23). `dim_friend_code` is a SIDE TABLE rather than a
  // dim_user column because user_data selects `dim_user *` — a new column
  // would reach old app builds whose local schema does not know it. It
  // streams only to its owner.
  Table('dim_friend_code', [
    Column.text('user_id'),
    Column.text('friend_code'),
    Column.text('created_date'),
  ]),
  // One ROW PER DIRECTION: this table streams only the caller's own outgoing
  // rows; the reciprocal half lives on the friend's device. A friendship is
  // the pair — the RPC writes both in one call, and the friends_data stream
  // matches only mutual pairs.
  Table(
    'friend_relationship',
    [
      Column.text('user_id'),
      Column.text('friend_user_id'),
      Column.text('created_date'),
      // The caller's private label for the friend (2026-10-25,
      // 20261025120000_friend_nicknames.sql). Null = no nickname. Nullable and
      // additive, so it needs no upload-map change: a local UPDATE queues a
      // composite-key PATCH, which database.dart already handles.
      Column.text('nickname'),
    ],
    indexes: [
      Index('user_idx', [IndexedColumn.ascending('user_id')]),
    ],
  ),
  Table(
    'dim_planned_session',
    [
      Column.text('session_id'),
      Column.text('user_id'),
      Column.text('name'),
      Column.text('notes'),
      Column.text('date_archived'),
      Column.text('created_date'),
      // Copy-on-add provenance. NULL = this workout originated here; set = this
      // is a program copy of the library workout it names. Plain ref (no FK):
      // an offline create→import must not be able to fail an FK on upload.
      Column.text('base_session_id'),
    ],
    indexes: [
      Index('user_idx', [IndexedColumn.ascending('user_id')]),
    ],
  ),
  Table('dim_pr_view_setting', [
    Column.text('pr_view_setting_id'),
    Column.text('user_id'),
    Column.text('exercise_id'),
    Column.text('axis_type'),
    Column.text('axis_value'),
  ]),
  Table(
    'dim_planned_session_program',
    [
      Column.text('planned_session_program_id'),
      Column.text('program_id'),
      Column.text('planned_session_id'),
      Column.text('user_id'),
      Column.integer('sequence_order'),
      Column.integer('day_of_week'),
      Column.integer('week_offset'),
      // The block this workout belongs to; NULL = a blockless program. The
      // server enforces (program_id, block_id) as a composite FK, so a workout
      // can only join a block of its own program.
      Column.text('block_id'),
    ],
    indexes: [
      Index('ps_idx', [IndexedColumn.ascending('planned_session_id')]),
      // A program's own membership rows — the workout list reads by program.
      Index('program_idx', [IndexedColumn.ascending('program_id')]),
    ],
  ),
  Table(
    'dim_planned_session_exercise',
    [
      Column.text('planned_exercise_id'),
      Column.text('planned_session_id'),
      Column.text('user_id'),
      Column.text('custom_exercise_id'),
      Column.integer('exercise_order'),
      Column.integer('is_archived'),
    ],
    indexes: [
      Index('session_idx', [IndexedColumn.ascending('planned_session_id')]),
    ],
  ),
  Table(
    'dim_planned_session_exercise_set',
    [
      Column.text('planned_set_id'),
      Column.text('planned_exercise_id'),
      Column.text('user_id'),
      Column.text('custom_variation_id'),
      Column.integer('set_number'),
      Column.text('target_weight'),
      Column.text('target_reps'),
      Column.text('target_notes'),
      Column.integer('is_archived'),
    ],
    indexes: [
      Index('pe_idx', [IndexedColumn.ascending('planned_exercise_id')]),
    ],
  ),
  Table(
    'fact_goal',
    [
      Column.text('goal_id'),
      Column.text('program_run_id'),
      Column.text('user_id'),
      Column.text('goal_text'),
      // Free-form notes about the goal itself (2026-10-08) — the target and its
      // label are target_* / goal_text, not this. See
      // 20261008120000_goal_description.sql.
      Column.text('goal_description'),
      Column.text('custom_exercise_id'),
      // The scope: a program, or a block of one. NULL program = standalone.
      // Dormant since goals went unattached (2026-10-08) — kept, not dropped.
      Column.text('program_id'),
      Column.text('block_id'),
      // The one variation the goal is scoped to; NULL = the plain exercise,
      // which is a scope of its own rather than a wildcard.
      Column.text('custom_variation_id'),
      Column.text('target_weight'),
      Column.integer('target_reps'),
      // The day the goal should be hit by (2026-10-19). NULL = no deadline.
      // See 20261019120000_goal_target_date.sql.
      Column.text('target_date'),
      // Every adjustment to target_date, oldest first, as JSON
      // [{from, to, changed_at}] — moving a deadline is a fact, not an
      // overwrite. NULL = never adjusted.
      Column.text('target_date_history_json'),
      Column.text('goal_created_date'),
      // `achieved_date` is deliberately absent — a goal's outcome is a per-run
      // fact now, frozen into fact_program_review.achievements_json at close.
      // See 20260928074745_program_goal_scoping.sql.
    ],
    indexes: [
      // Every goal read is "this user's goals" — the goals tab, the G badge's
      // derivation and the pickers all filter on it.
      Index('user_idx', [IndexedColumn.ascending('user_id')]),
    ],
  ),
  Table(
    'fact_goal_target',
    [
      Column.text('goal_target_id'),
      Column.text('goal_id'),
      Column.text('user_id'),
      // 1-based, dense: the order the requirements are listed and matched in.
      Column.integer('target_set_order'),
      // Numeric on the server, text in the mirror — the same mapping
      // fact_goal.target_weight uses.
      Column.text('target_weight'),
      Column.integer('target_reps'),
    ],
    indexes: [
      // One goal's requirements, in order — the only read there is.
      Index('goal_idx', [IndexedColumn.ascending('goal_id')]),
      // The friends stream pages children by user (one bucket per friend).
      Index('user_idx', [IndexedColumn.ascending('user_id')]),
    ],
  ),
]);
