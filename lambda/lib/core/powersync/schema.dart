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
  Table('fact_session', [
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
  ]),
  Table('dim_exercise', [
    Column.text('custom_exercise_id'),
    Column.text('user_id'),
    Column.text('exercise_name'),
    Column.text('date_archived'),
  ]),
  Table('dim_variation', [
    Column.text('custom_variation_id'),
    Column.text('user_id'),
    Column.text('variation_name'),
    Column.text('date_archived'),
  ]),
  Table('fact_bodyweight', [
    Column.text('user_weight_id'),
    Column.text('user_id'),
    Column.text('user_weight'),
    Column.text('user_weight_date'),
    Column.text('created_date'),
  ]),
  Table('fact_session_exercise', [
    Column.text('session_exercise_id'),
    Column.text('session_id'),
    Column.text('user_id'),
    Column.text('custom_exercise_id'),
    Column.integer('exercise_order'),
    Column.text('planned_exercise_id'),
  ]),
  Table('fact_session_exercise_set', [
    Column.text('session_exercise_set_id'),
    Column.text('session_exercise_id'),
    Column.text('user_id'),
    Column.text('custom_variation_id'),
    Column.integer('set_number'),
    Column.text('weight'),
    Column.text('reps'),
    Column.text('notes'),
    Column.text('planned_set_id'),
  ]),
  Table('dim_program', [
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
  ]),
  Table('fact_program_run', [
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
  ]),
  // An ordered, duration-bounded phase of a program, holding workouts and (from
  // the goals phase) goals. A program either uses blocks or doesn't — never
  // mixed. `date_archived` rather than `is_archived` because a block is named,
  // dated and user-visible with its own run/review trail to keep browsable.
  Table('dim_program_block', [
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
  ]),
  // The checkpoints a program's run passes through — one row per review, per
  // proposed change, and per run close — AND the snapshot each one cut.
  // `completed_date` NULL is what makes a review open; there is no status column
  // to keep in sync with it. `snapshot_content` is the same `ProgramContent`
  // document the retired revision table held, written when the review completes.
  //
  // SCOPE — exactly one of: the program's own (`block_id` and `session_id` both
  // null), a block (`block_id`), or one planned session (`session_id`). The two
  // ids are never both set; the server enforces it, and `scheduleReview`
  // refuses it client-side so the row cannot reach the CHECK at all.
  Table('fact_program_review', [
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
    Column.text('achievements_json'),
    Column.text('created_date'),
  ]),
  Table('dim_lesson', [
    Column.text('lesson_id'),
    Column.text('user_id'),
    Column.text('custom_exercise_id'),
    Column.text('lesson_text'),
    Column.integer('pinned'),
    Column.integer('is_archived'),
    Column.text('lesson_created_date'),
    Column.text('session_id'),
  ]),
  Table('coaching_relationship', [
    Column.text('coach_user_id'),
    Column.text('athlete_user_id'),
    Column.text('created_date'),
  ]),
  Table('dim_planned_session', [
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
  ]),
  Table('dim_pr_view_setting', [
    Column.text('pr_view_setting_id'),
    Column.text('user_id'),
    Column.text('exercise_id'),
    Column.text('axis_type'),
    Column.text('axis_value'),
  ]),
  Table('dim_planned_session_program', [
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
  ]),
  Table('dim_planned_session_exercise', [
    Column.text('planned_exercise_id'),
    Column.text('planned_session_id'),
    Column.text('user_id'),
    Column.text('custom_exercise_id'),
    Column.integer('exercise_order'),
    Column.integer('is_archived'),
  ]),
  Table('dim_planned_session_exercise_set', [
    Column.text('planned_set_id'),
    Column.text('planned_exercise_id'),
    Column.text('user_id'),
    Column.text('custom_variation_id'),
    Column.integer('set_number'),
    Column.text('target_weight'),
    Column.text('target_reps'),
    Column.text('target_notes'),
    Column.integer('is_archived'),
  ]),
  Table('fact_goal', [
    Column.text('goal_id'),
    Column.text('program_run_id'),
    Column.text('user_id'),
    Column.text('goal_text'),
    Column.text('custom_exercise_id'),
    // The scope: a program, or a block of one. NULL program = standalone.
    Column.text('program_id'),
    Column.text('block_id'),
    // The one variation the goal is scoped to; NULL = the plain exercise,
    // which is a scope of its own rather than a wildcard.
    Column.text('custom_variation_id'),
    Column.text('target_weight'),
    Column.integer('target_reps'),
    Column.text('goal_created_date'),
    // `achieved_date` is deliberately absent — a goal's outcome is a per-run
    // fact now, frozen into fact_program_review.achievements_json at close.
    // See 20260927000004_program_goal_scoping.sql.
  ]),
]);
