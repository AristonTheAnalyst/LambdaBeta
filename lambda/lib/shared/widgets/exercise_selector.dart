import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import './session_chevron_button.dart';

/// What an exercise name wears when it differs from a second reading: a
/// green **plus** for one the other reading did not hold, a red **minus**
/// for one it did and the side on screen does not.
///
/// Two readers: a review's frozen sides (the eye flips, and the same name
/// can wear the plus from one side and the minus from the other) and a live
/// session's plan-diff, where an exercise added beyond the plan wears the
/// plus (2026-10-13). Nothing is stored — the mark is derived wherever a
/// second reading exists.
enum ExerciseMark {
  added(Icons.add_circle, 14),
  removed(Icons.remove_circle, 14);

  const ExerciseMark(this.icon, this.size);

  /// The glyph the name wears — the plus or minus inside a disc, because a
  /// bare stroke at this size reads as a hyphen, or as a smudge, against the
  /// name it is about (2026-10-12). Colour resolves at draw time — the tokens
  /// are getters over the live theme, so no enum constant can hold one — and
  /// is [AppColors.success] for [added], [AppColors.danger] for [removed].
  final IconData icon;

  /// How large the glyph draws — the disc's size.
  final double size;
}

/// The selector's chevron recipe (2026-10-22): 40px target, 24px glyph, the
/// same `chevron_*` the date bar draws — the lab's one chevron species, so
/// the selector's flanks and the floor's date bar never read as two sizes of
/// the same control. The field between them stands at the same 40.
/// [SessionChevronButton] owns the recipe; [kExerciseSelectorArrowSize] is
/// the name this widget's geometry reads it by.
const double kExerciseSelectorArrowSize = SessionChevronButton.kSessionChevronSize;

/// The height both exercise pickers cap their scrolling list at — this
/// selector's popover and the Add/Remove Exercises sheet
/// (`add_exercise_modal.dart`) read this one value, so the one picker's two
/// shapes cannot drift (2026-10-26).
///
/// Half the screen: the old fixed 260 showed about five rows, which asks the
/// user to scroll before they can look at their own library. A short screen
/// (landscape) keeps the old cap rather than shrinking below it.
double exercisePickerListCap(BuildContext context) {
  final half = MediaQuery.sizeOf(context).height * 0.5;
  return half < _kExercisePickerListFloor ? _kExercisePickerListFloor : half;
}

/// The old fixed cap — now the floor a short screen may not go under.
const double _kExercisePickerListFloor = 260;

/// The gap the popover hangs under its field, and the margin it keeps from
/// the screen's bottom edge — the same two numbers the popover's placement
/// and its height budget are computed from.
const double _kPopoverGap = 4;
const double _kPopoverMargin = 8;

/// The workout exercise selector — a field that opens an anchored popover
/// over the screen: the selected exercise shows highlighted, up/down arrows
/// reorder, and Add/Remove Exercises is pinned at the bottom, where the
/// caller's exercise picker both adds and removes. The caller owns the list;
/// every action reports back through callbacks.
class ExerciseSelector extends StatefulWidget {
  const ExerciseSelector({
    super.key,
    required this.exercises,
    required this.activeIndex,
    required this.onSelect,
    required this.onMove,
    required this.onAdd,
    this.marks = const [],
    this.deleted = const [],
    this.planned = false,
  });

  /// Display names, in order.
  final List<String> exercises;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// One mark per name, parallel to [exercises]. A null entry, a list that
  /// stops short, or no list at all leaves that name bare — an unmarked name
  /// draws nothing, not even the gap its mark would take. Reviews and the
  /// live session's plan-diff fill these (2026-10-13).
  final List<ExerciseMark?> marks;

  /// One flag per name, parallel to [exercises]: the exercise was deleted
  /// from the workout (every row it holds is flagged) and its name wears the
  /// deleted box — the deleted SET row's exact chrome ([deletedBox]), the
  /// text itself left alone (2026-10-14). A list that stops short leaves the
  /// rest plain.
  final List<bool> deleted;

  /// The closed field wears the planned container — the card no longer draws
  /// a blue rim, so the selector carries the plan's provenance (2026-10-23).
  /// Deleted still outranks it: a deleted exercise is red, not blue.
  final bool planned;

  /// Reorder: move [index] by [direction] (-1 up, +1 down).
  /// Null greys the reorder arrows (read-only contexts).
  final void Function(int index, int direction)? onMove;

  /// Null greys the Add/Remove Exercises row (kept visible but inert so the
  /// popover still reads complete in read-only contexts).
  final VoidCallback? onAdd;

  @override
  State<ExerciseSelector> createState() => _ExerciseSelectorState();
}

class _ExerciseSelectorState extends State<ExerciseSelector> {
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  double _fieldWidth = 0;

  /// The popover's height when it opens: the picker's cap, narrowed to the
  /// room the screen has left below the field.
  double _popoverHeight = 0;
  bool _open = false;

  void _close() {
    _portal.hide();
    if (_open) setState(() => _open = false);
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _fieldWidth = box?.size.width ?? 0;
      // The popover opens downward from the field. Half the screen is the
      // picker's cap, but the field is not always near the top — the old 260
      // could not reach the bottom edge, and this can — so it never grows
      // past the screen below the field (2026-10-26). The 260 floor keeps a
      // cramped layout as usable as it was before the cap moved.
      var height = exercisePickerListCap(context);
      if (box != null) {
        final fieldBottom = box.localToGlobal(Offset.zero).dy + box.size.height;
        final room =
            MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).bottom -
            fieldBottom -
            _kPopoverGap -
            _kPopoverMargin;
        if (room < height) height = room;
      }
      _popoverHeight = height < _kExercisePickerListFloor
          ? _kExercisePickerListFloor
          : height;
      _open = true;
    });
    _portal.show();
  }

  /// Whether the [i]-th name is a deleted exercise — drawn red wherever the
  /// name appears.
  bool _isDeleted(int i) => i < widget.deleted.length && widget.deleted[i];

  /// The glyph a marked name wears, riding directly after it: the name
  /// ellipsizes to its left, so a long one narrows rather than pushing its
  /// mark out of the field. An unmarked name draws nothing at all. The field
  /// and the popover rows draw the same marks (2026-10-23 — the restore dot
  /// that once waited for the popover is gone: the deleted view lists every
  /// deleted exercise itself).
  Widget _mark(int i) {
    final mark = i < widget.marks.length ? widget.marks[i] : null;
    if (mark == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        mark.icon,
        size: mark.size,
        color: switch (mark) {
          ExerciseMark.added => AppColors.success,
          ExerciseMark.removed => AppColors.danger,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // The field fills the full width its parent offers.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Left/right flanking arrows — step between exercises without
            // opening the popover. Greyed at the ends of the list. The glyph
            // is the date bar's own (`chevron_*` at 24) in a 40px target
            // (2026-10-22): one chevron species for the whole session stage.
            _arrow(
              Icons.chevron_left,
              widget.exercises.length > 1 && widget.activeIndex > 0,
              () => widget.onSelect(widget.activeIndex - 1),
              key: const ValueKey('exercise-selector-prev'),
              semanticsLabel: 'Previous exercise',
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: CompositedTransformTarget(
                link: _link,
                child: GestureDetector(
                  key: const ValueKey('exercise-selector-field'),
                  onTap: _toggle,
                  child: Container(
                    key: _fieldKey,
                    // One height with the arrows it stands between: the
                    // field used to be its text's height (~35), leaving the
                    // 40 boxes beside it standing proud (2026-10-22).
                    height: kExerciseSelectorArrowSize,
                    // Glass compact — the neutral translucent treatment,
                    // swapped for the deleted box while it shows a deleted
                    // exercise (2026-10-14), and for the planned container
                    // while the exercise comes from a plan (2026-10-23):
                    // the plan's own soft highlight, one recipe.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: _isDeleted(widget.activeIndex)
                        ? deletedBox()
                        : widget.planned
                        ? lambdaBox(ContainerTone.planned, radius: AppRadius.md)
                        : BoxDecoration(
                            color: AppColors.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: AppColors.primary.withAlpha(77),
                            ),
                          ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.exercises.isEmpty
                                      ? ''
                                      : widget.exercises[widget.activeIndex],
                                  // Single line: without it the name wraps and
                                  // grows the field taller instead of
                                  // shortening.
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.sm,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              _mark(widget.activeIndex),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Chevron right of the exercise name — the field's
                        // dropdown affordance. Points up while the popover
                        // is open.
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _arrow(
              Icons.chevron_right,
              widget.exercises.length > 1 &&
                  widget.activeIndex < widget.exercises.length - 1,
              () => widget.onSelect(widget.activeIndex + 1),
              key: const ValueKey('exercise-selector-next'),
              semanticsLabel: 'Next exercise',
            ),
          ],
        ),
        // The popover lives in the app's Overlay, anchored to the field via
        // the LayerLink — exact field width, fixed height, scrollable rows,
        // sticky Add Exercise.
        OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _open
              ? Stack(
                  children: [
                    // Scrim barrier — dims the screen behind the popover and
                    // dismisses on any tap outside it.
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _close,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    CompositedTransformFollower(
                      link: _link,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.topLeft,
                      offset: const Offset(0, _kPopoverGap),
                      child: Container(
                        key: const ValueKey('exercise-selector-popover'),
                        width: _fieldWidth,
                        constraints: BoxConstraints(maxHeight: _popoverHeight),
                        decoration: lambdaBox(
                          ContainerTone.surface,
                          radius: AppRadius.md,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < widget.exercises.length;
                                      i++
                                    )
                                      _row(i),
                                  ],
                                ),
                              ),
                            ),
                            _addRow(),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _row(int i) {
    final selected = i == widget.activeIndex;
    return GestureDetector(
      onTap: () {
        if (selected) {
          // Already selected — just close the menu.
          _close();
          return;
        }
        widget.onSelect(i);
        _close();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // The selected exercise shows with the neutral glass highlight; a
        // deleted one wears the deleted box — the set row's exact chrome,
        // one recipe (2026-10-14).
        decoration: _isDeleted(i)
            ? deletedBox()
            : BoxDecoration(
                color: selected
                    ? AppColors.primary.withAlpha(26)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.5),
                ),
              ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.exercises[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        // The container carries the deletion — the name's own
                        // colour stays the row's reading.
                        color: selected
                            ? AppColors.primary
                            : AppColors.inkSecondary,
                      ),
                    ),
                  ),
                  _mark(i),
                ],
              ),
            ),
            _arrow(
              Icons.keyboard_arrow_up,
              widget.onMove != null && i > 0,
              () => widget.onMove!(i, -1),
              size: 28,
              iconSize: 15,
              semanticsLabel: 'Move up',
            ),
            const SizedBox(width: 2),
            _arrow(
              Icons.keyboard_arrow_down,
              widget.onMove != null && i < widget.exercises.length - 1,
              () => widget.onMove!(i, 1),
              size: 28,
              iconSize: 15,
              semanticsLabel: 'Move down',
            ),
          ],
        ),
      ),
    );
  }

  /// Arrow button — [size] is the full tap target
  /// ([kExerciseSelectorArrowSize] for the flanking field arrows, chevron
  /// 28×28 inside the popover rows). Drawn by the shared
  /// [SessionChevronButton], so the flanks are one recipe with the date
  /// bar's session arrows.
  Widget _arrow(
    IconData icon,
    bool enabled,
    VoidCallback onTap, {
    Key? key,
    double size = kExerciseSelectorArrowSize,
    double iconSize = SessionChevronButton.kSessionChevronIconSize,
    required String semanticsLabel,
  }) {
    return SessionChevronButton(
      key: key,
      icon: icon,
      enabled: enabled,
      onPressed: onTap,
      size: size,
      iconSize: iconSize,
      semanticsLabel: semanticsLabel,
    );
  }

  /// Pinned at the bottom of the popover — the caller opens its own
  /// exercise picker, which is where exercises are both added and removed.
  /// When [widget.onAdd] is null the row stays visible but renders greyed and
  /// inert, so read-only contexts keep the popover's shape without a dead
  /// action.
  Widget _addRow() {
    final enabled = widget.onAdd != null;
    final color = enabled
        ? AppColors.primary
        : AppColors.muted.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: enabled
          ? () {
              _close();
              widget.onAdd!();
            }
          : () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: enabled ? glassBox(AppColors.primary) : null,
        child: Row(
          children: [
            Icon(Icons.add, size: 16, color: color),
            const SizedBox(width: AppSpacing.sm),
            // The popover is the field's width, and the field narrows as the
            // chevrons around it grow (2026-10-22): the label ellipsizes on
            // the planner's inset card instead of overflowing its row.
            Expanded(
              child: Text(
                'Add/Remove Exercises',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
