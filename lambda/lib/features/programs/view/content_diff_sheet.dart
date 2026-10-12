import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_content.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/program_content_diff.dart';

/// The sheet's heading where the app supplies its own. Every review surface
/// wears it — the bar's Changes, the history panel's, a snapshot's — and a
/// review with a title of its own overrides it, which is what that title is
/// for.
const String kReviewChangesTitle = 'Review Changes Summary';

/// What changed between two checkpoints of a program.
///
/// Pure data in, like `showPrModal`: it decodes the two documents, diffs them
/// and renders. Nothing is fetched and nothing is written — a comparison is a
/// read of two immutable records.
///
/// The shape is a card per thing: a card per exercise — "Changes made" or
/// "No changes", so an exercise that held still is an answer too — and a card
/// per block or goal that moved, with the changes as lines of prose under the
/// name. The only numbers are the two counts at the top.
///
/// An exercise card carries no lines: the card answers "did this move", and
/// where a screen holds the exercise ([onExerciseTap]) a tap takes it there —
/// the exercise itself is the detail. A removed exercise keeps one line,
/// "removed": its card has nowhere to go, and gone must not read as edited.
/// Blocks and goals keep their lines too — nothing else on screen shows them.
///
/// [title] and [subtitle] are supplied by the caller because there are two
/// questions this answers — "what changed since the last checkpoint?" and
/// "what would this proposed change do?" — and they are the same comparison
/// with a different header. [subtitle] is optional: the review bar's sheet
/// answers inside one workout and has no second side to name.
void showContentDiffSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required ProgramContent? before,
  required ProgramContent? after,
  Map<String, String> exerciseNames = const {},
  Map<String, String> variationNames = const {},
  String? beforeMissingNote,
  String? emptyNote,
  ValueChanged<String>? onExerciseTap,
}) {
  showLambdaModal(
    context,
    child: SafeArea(
      child: _ContentDiffSheet(
        title: title,
        subtitle: subtitle,
        before: before,
        after: after,
        exerciseNames: exerciseNames,
        variationNames: variationNames,
        beforeMissingNote: beforeMissingNote,
        emptyNote: emptyNote,
        onExerciseTap: onExerciseTap,
      ),
    ),
  );
}

class _ContentDiffSheet extends StatelessWidget {
  const _ContentDiffSheet({
    required this.title,
    required this.subtitle,
    required this.before,
    required this.after,
    required this.exerciseNames,
    required this.variationNames,
    required this.beforeMissingNote,
    required this.emptyNote,
    required this.onExerciseTap,
  });

  final String title;
  final String? subtitle;
  final ProgramContent? before;
  final ProgramContent? after;
  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  /// Shown in place of the list when [before] is null. Only the caller knows
  /// WHY it is null — a snapshot that failed to decode and one that was never
  /// recorded both arrive here as null — and "no earlier version recorded"
  /// reads very differently from "saved by a newer app" to the person holding
  /// the phone.
  final String? beforeMissingNote;

  /// Shown when both sides decode but nothing changed. Defaults to the
  /// checkpoint wording; a comparison taken mid-pass is not a checkpoint.
  final String? emptyNote;

  /// Opens one exercise of the workout the sheet is about, wherever a screen
  /// holds it — called with the group's `planned_exercise_id` after the sheet
  /// closes itself. Null leaves the exercise cards inert, which is every
  /// surface with no screen holding the exercise underneath it: the history
  /// panel's timeline.
  final ValueChanged<String>? onExerciseTap;

  @override
  Widget build(BuildContext context) {
    final readable = before != null && after != null;
    final diff = readable
        ? diffContent(
            before,
            after,
            exerciseNames: exerciseNames,
            variationNames: variationNames,
          )
        : const ContentDiff.empty();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (!readable)
            _Note(
              beforeMissingNote ??
                  "One of these versions can't be displayed — it was saved by "
                      'a newer version of the app.',
            )
          else if (diff.isEmpty)
            _Note(
              emptyNote ??
                  'The contents are identical. This checkpoint recorded no '
                      'changes — that is worth knowing on its own.',
            )
          else
            ConstrainedBox(
              // The sheet sizes to its content, so a long diff needs its own
              // ceiling or it would run past the top of the screen.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                // The counts are content ABOUT the cards, so they live inside
                // the one ceiling and scroll with them.
                children: [..._stats(), ..._sections(context, diff)],
              ),
            ),
        ],
      ),
    );
  }

  /// The two counts and their deltas — the short answer, before the cards get
  /// specific.
  ///
  /// Only called where both sides decoded (the branch that renders the
  /// sections), so the fields are known non-null and the delta is never asked
  /// about a missing side.
  List<Widget> _stats() {
    final before = this.before!;
    final after = this.after!;
    return [
      _StatLine(
        label: 'SETS',
        value: after.setCount,
        delta: after.setCount - before.setCount,
      ),
      _StatLine(
        label: 'EXERCISES',
        value: after.exerciseCount,
        delta: after.exerciseCount - before.exerciseCount,
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  /// The change list: blocks first (the program's outer shape, as the diff
  /// emits them), then a section per workout — its name, its own changes as
  /// loose lines, a card per exercise with any removed group carded after the
  /// survivors — then goals.
  ///
  /// A workout with nothing changed in it is left out entirely; once a
  /// workout has changed at all, EVERY exercise in it is carded, because
  /// "No changes" is the answer the card exists to give. An exercise card
  /// lists nothing: it answers whether the exercise moved, and where a screen
  /// holds it the tap opens it. A removed group keeps one line to say so —
  /// its card cannot open anywhere, so silence would let it pass for present.
  /// A removed workout has no exercises left to card, so it is its name and
  /// its line.
  List<Widget> _sections(BuildContext context, ContentDiff diff) {
    final before = this.before!;
    final after = this.after!;
    final widgets = <Widget>[];

    for (final group in _groupedBy(
      diff.changes.where((c) => c.entity == ContentEntity.block),
    ).values) {
      widgets.add(
        _ChangeCard(title: group.last.label, changed: true, changes: group),
      );
    }

    final alive = {for (final s in after.sessions) s.sessionId};
    for (final session in [
      ...after.sessions,
      for (final s in before.sessions)
        if (!alive.contains(s.sessionId)) s,
    ]) {
      final own = [
        for (final change in diff.changes)
          if (change.sessionId == session.sessionId) change,
      ];
      if (own.isEmpty) continue;

      widgets.add(_Heading(name: session.name, first: widgets.isEmpty));
      for (final change in own.where((c) => c.entity == ContentEntity.session)) {
        widgets.add(_Line(change: change, anchor: session.name));
      }

      // A workout that left has nothing under it to card.
      if (!alive.contains(session.sessionId)) continue;

      final grouped = _groupedBy(
        own.where((c) => c.entity != ContentEntity.session),
        // A set change's own id is the set's; the card it belongs to is keyed
        // by the exercise group, which is exactly what `plannedExerciseId`
        // holds — and holds across a lift swap.
        by: (change) => change.plannedExerciseId!,
      );
      final carded = {
        for (final exercise in session.exercises) exercise.plannedExerciseId,
      };
      for (final exercise in session.exercises) {
        final id = exercise.plannedExerciseId;
        final changes = grouped[id] ?? const [];
        widgets.add(
          _ChangeCard(
            title: _groupTitle(exercise, changes),
            changed: changes.isNotEmpty,
            onTap: onExerciseTap == null
                ? null
                : () => _openExercise(context, id),
          ),
        );
      }
      // Groups the workout no longer holds — their own cards, after the
      // survivors, in the order the diff saw them leave. One line each, and
      // it is the exercise's own: the set changes under it are all "removed"
      // too, and repeating that per set is the noise this sheet shed.
      for (final entry in grouped.entries) {
        if (carded.contains(entry.key)) continue;
        widgets.add(
          _ChangeCard(
            title: _groupTitle(null, entry.value),
            changed: true,
            changes: [
              for (final change in entry.value)
                if (change.entity == ContentEntity.exercise) change,
            ],
          ),
        );
      }
    }

    for (final group in _groupedBy(
      diff.changes.where((c) => c.entity == ContentEntity.goal),
    ).values) {
      widgets.add(
        _ChangeCard(title: group.last.label, changed: true, changes: group),
      );
    }

    return widgets;
  }

  /// Closes the sheet first — so the switch lands with the sheet already
  /// leaving — then hands the group's id to the screen that can open it.
  void _openExercise(BuildContext context, String plannedExerciseId) {
    Navigator.of(context).pop();
    onExerciseTap!.call(plannedExerciseId);
  }

  /// An exercise card's title: the live name when the map resolves it, else
  /// the name the group's own changes carry — a removed group has no row left
  /// to read — else the generic noun the diff itself falls back to.
  String _groupTitle(ContentExercise? exercise, List<ContentChange> changes) {
    final id = exercise?.exerciseId;
    if (id != null) {
      final name = exerciseNames[id];
      if (name != null && name.trim().isNotEmpty) return name;
    }
    for (final change in changes.reversed) {
      final name = change.exerciseName;
      if (name != null && name.trim().isNotEmpty) return name;
    }
    return 'Exercise';
  }
}

/// Changes grouped by a key of the reader's choosing, first-seen order.
Map<String, List<ContentChange>> _groupedBy(
  Iterable<ContentChange> changes, {
  String Function(ContentChange change)? by,
}) {
  final grouped = <String, List<ContentChange>>{};
  for (final change in changes) {
    grouped.putIfAbsent(by?.call(change) ?? change.id, () => []).add(change);
  }
  return grouped;
}

/// One change as a line of prose: `Set 2 added — 70 × 5`, `Set 1 — 60 × 5 →
/// 65 × 5`, `removed`.
///
/// The subject is dropped when it names the card the line sits on — the title
/// above it already said so — and an edit carries no verb because its detail
/// names its own ("renamed: …", "variation: …"). A note's detail is headed
/// with its field, because two prose previews joined by an arrow would
/// otherwise read as a target edit.
String _lineText(ContentChange change, String anchor) {
  final subject = change.label == anchor ? null : change.label;
  final detail = change.detail;
  final body = detail == null
      ? null
      : change.oldText != null || change.newText != null
          ? 'note: $detail'
          : detail;
  final verb = switch (change.kind) {
    ContentChangeKind.added => 'added',
    ContentChangeKind.removed => 'removed',
    ContentChangeKind.moved => 'moved',
    ContentChangeKind.edited => null,
  };
  final head = <String>[
    ?subject,
    ?verb,
  ].join(' ');
  if (body == null) return head.isEmpty ? change.label : head;
  return head.isEmpty ? body : '$head — $body';
}

/// A workout's name, over its section — the diff emits a workout's changes
/// together, so the section is the grouping and this is its anchor.
class _Heading extends StatelessWidget {
  const _Heading({required this.name, required this.first});

  final String name;

  /// Whether this is the list's first entry — the first takes no top of its
  /// own, because the counts above end in a gap.
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          top: first ? 0 : AppSpacing.md,
          bottom: AppSpacing.xs,
        ),
        child: Text(
          name.toUpperCase(),
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.accent,
          ),
        ),
      );
}

/// One subject's changes: its name, what that amounts to, and the changes as
/// lines. The one card shape in the sheet — an exercise, a block, a goal — so
/// "No changes" reads the same wherever it appears.
///
/// [changed] drives the status text alone. The container is the same either
/// way — a card is a card, and the verdict is the status line's to say, not
/// the fill's.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.title,
    required this.changed,
    this.changes = const [],
    this.onTap,
  });

  final String title;

  /// Whether the card reads "Changes made" or "No changes".
  final bool changed;

  /// The change lines under the title. Empty for an exercise card, whose
  /// answer is its status; the lines' subjects are dropped against [title].
  final List<ContentChange> changes;

  /// Opens the subject on the screen that holds it. Null leaves the card
  /// inert — no tap, and no chevron promising one.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final card = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      // One tier above the sheet's own fill, changed or not.
      decoration: lambdaBox(ContainerTone.ghost),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                changed ? 'Changes made' : 'No changes',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w700,
                  color: changed ? AppColors.accent : AppColors.muted,
                ),
              ),
              // The same rung a note line wears, for the same reason: there
              // is somewhere behind this.
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_right, size: 15, color: AppColors.muted),
              ],
            ],
          ),
          for (var i = 0; i < changes.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? AppSpacing.sm : AppSpacing.xs,
              ),
              child: _Line(change: changes[i], anchor: title),
            ),
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

/// One change rendered as a line of prose under a card's title — or under a
/// workout heading, where the card would only repeat the name.
///
/// A note edit keeps its rung: the line previews the pair, and a tap opens
/// both whole.
class _Line extends StatelessWidget {
  const _Line({required this.change, required this.anchor});

  final ContentChange change;

  /// The name the line is read under — a card's title or a workout's heading.
  /// A subject that repeats it is dropped.
  final String anchor;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      _lineText(change, anchor),
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        color: AppColors.muted,
      ),
    );
    if (change.oldText == null && change.newText == null) return text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showNoteChange(context, change),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: text),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, size: 15, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// The full pair behind a `note: was → now` line: what the note said before
/// the change and what it says now, each verbatim.
///
/// The line carries a capped preview because a line is one line; a note has
/// no length limit, so the pair is read here, whole. The whole thing scrolls
/// under a ceiling, for the note that runs long.
void _showNoteChange(BuildContext context, ContentChange change) {
  showLambdaModal<void>(
    context,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Note changed',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _changeTitle(change),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _NoteBlock(label: 'BEFORE', text: change.oldText),
                const SizedBox(height: AppSpacing.sm),
                _NoteBlock(label: 'AFTER', text: change.newText),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The change's subject as the popup names it: the change's own line, plus
/// the workout a set belongs to — the section has a heading above it for
/// that, and a popup has none.
String _changeTitle(ContentChange change) {
  final exercise = change.entity == ContentEntity.set
      ? change.exerciseName
      : null;
  final head = exercise == null ? change.label : '${change.label} · $exercise';
  final session = change.sessionName;
  if (session == null || session == change.label) return head;
  return '$head · $session';
}

/// One side of a note change: the text verbatim, or the absence named —
/// "(none)" on the line's preview and "No note" here are the same fact.
class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.label, required this.text});

  final String label;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final body = text?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: lambdaBox(ContainerTone.ghost),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body.isEmpty ? 'No note' : body,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: body.isEmpty ? AppColors.muted : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One count, its current value, and how it moved — `SETS 22 +2`. The signed
/// delta carries the colour (`−` is U+2212, the same minus [ContentDiff.summary]
/// prints), and ±0 stays grey: unchanged is information, not a change.
class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.label,
    required this.value,
    required this.delta,
  });

  final String label;
  final int value;
  final int delta;

  @override
  Widget build(BuildContext context) {
    final (glyph, color) = delta > 0
        ? ('+$delta', AppColors.success)
        : delta < 0
            ? ('−${-delta}', AppColors.danger)
            : ('±0', AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            label,
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.muted,
            ),
          ),
          const Spacer(),
          Text(
            '$value',
            style: AppFonts.mono(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            glyph,
            style: AppFonts.mono(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.muted,
        ),
      );
}
