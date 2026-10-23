// LAB COPY — the /dev/pr-lab layout sandbox's own copy of a shared
// widget. Never import this from a production screen. Edit freely: nothing
// here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';

/// The stage's chevron recipe, shared by both flanking pairs: the selector's
/// left/right arrows and the date bar's above them. One 40px target, one 24
/// glyph, one 6 corner — the pair used to be a 32 box around an 18
/// `keyboard_arrow_*` (a smaller species of chevron than the date bar's), and
/// the date bar a 48 box on a 2 corner (a square beside a rounded square),
/// so the two controls never quite agreed (2026-10-21).
const double kPrLabSelectorArrowSize = 40;
const double kPrLabSelectorArrowGlyph = 24;
const double kPrLabSelectorArrowRadius = 6;

/// What an exercise name wears when it differs from a second reading: a
/// green **plus** for one the other reading did not hold, a red **minus**
/// for one it did and the side on screen does not.
///
/// Two readers: a review's frozen sides (the eye flips, and the same name
/// can wear the plus from one side and the minus from the other) and a live
/// session's plan-diff, where an exercise added beyond the plan wears the
/// plus (2026-10-13). Nothing is stored — the mark is derived wherever a
/// second reading exists.
enum PrLabExerciseMark {
  added(Icons.add_circle, 14),
  removed(Icons.remove_circle, 14),

  /// The accent **dot** marking the slot a deleted exercise will be restored
  /// to — drawn while the live session views a deleted exercise, on the name
  /// seated at that spot (2026-10-14). A dot, not a disc: it names a place
  /// on the bar, not a claim about the exercise.
  restore(Icons.circle, 9);

  const PrLabExerciseMark(this.icon, this.size);

  /// The glyph the name wears — the plus or minus inside a disc, because a
  /// bare stroke at this size reads as a hyphen, or as a smudge, against the
  /// name it is about (2026-10-12). Colour resolves at draw time — the tokens
  /// are getters over the live theme, so no enum constant can hold one — and
  /// is [AppColors.success] for [added], [AppColors.danger] for [removed],
  /// [AppColors.accent] for [restore].
  final IconData icon;

  /// How large the glyph draws — the disc size for the plus/minus, smaller
  /// for the dot, which only marks a spot.
  final double size;
}

/// The workout exercise selector — a field that opens an anchored popover
/// over the screen: the selected exercise shows highlighted, up/down arrows
/// reorder, and Add/Remove Exercises is pinned at the bottom, where the
/// caller's exercise picker both adds and removes. The caller owns the list;
/// every action reports back through callbacks.
class PrLabExerciseSelector extends StatefulWidget {
  const PrLabExerciseSelector({
    super.key,
    required this.exercises,
    required this.activeIndex,
    required this.onSelect,
    required this.onMove,
    required this.onAdd,
    this.marks = const [],
    this.deleted = const [],
  });

  /// Display names, in order.
  final List<String> exercises;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// One mark per name, parallel to [exercises]. A null entry, a list that
  /// stops short, or no list at all leaves that name bare — an unmarked name
  /// draws nothing, not even the gap its mark would take. Reviews and the
  /// live session's plan-diff fill these (2026-10-13).
  final List<PrLabExerciseMark?> marks;

  /// One flag per name, parallel to [exercises]: the exercise was deleted
  /// from the workout (every row it holds is flagged) and its name wears the
  /// deleted box — the deleted SET row's exact chrome ([deletedBox]), the
  /// text itself left alone (2026-10-14). A list that stops short leaves the
  /// rest plain.
  final List<bool> deleted;

  /// Reorder: move [index] by [direction] (-1 up, +1 down).
  /// Null greys the reorder arrows (read-only contexts).
  final void Function(int index, int direction)? onMove;

  /// Null greys the Add/Remove Exercises row (kept visible but inert so the
  /// popover still reads complete in read-only contexts).
  final VoidCallback? onAdd;

  @override
  State<PrLabExerciseSelector> createState() => _PrLabExerciseSelectorState();
}

class _PrLabExerciseSelectorState extends State<PrLabExerciseSelector> {
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  double _fieldWidth = 0;
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
      _open = true;
    });
    _portal.show();
  }

  /// Whether the [i]-th name is a deleted exercise — drawn red wherever the
  /// name appears.
  bool _isDeleted(int i) => i < widget.deleted.length && widget.deleted[i];

  /// The glyph a marked name wears, riding directly after it: the name
  /// ellipsizes to its left, so a long one narrows rather than pushing its
  /// mark out of the field. An unmarked name draws nothing at all.
  Widget _mark(int i, {bool field = false}) {
    final mark = i < widget.marks.length ? widget.marks[i] : null;
    // The restore dot names a PLACE IN THE LIST — the closed field holds one
    // exercise, so the dot waits for the popover (2026-10-14).
    if (mark == null || (field && mark == PrLabExerciseMark.restore)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        mark.icon,
        size: mark.size,
        color: switch (mark) {
          PrLabExerciseMark.added => AppColors.success,
          PrLabExerciseMark.removed => AppColors.danger,
          PrLabExerciseMark.restore => AppColors.accent,
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
            // is the date bar's own (`chevron_*` at 24) in a 40px target:
            // the keyboard-arrow pair at 18 read as a smaller species of
            // chevron beside the rest of the stage (2026-10-21).
            _arrow(
              Icons.chevron_left,
              widget.exercises.length > 1 && widget.activeIndex > 0,
              () => widget.onSelect(widget.activeIndex - 1),
              key: const ValueKey('exercise-selector-prev'),
              size: kPrLabSelectorArrowSize,
              iconSize: kPrLabSelectorArrowGlyph,
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
                    // One height with the arrows it stands between: the field
                    // used to be its text's height (~35), leaving the 40
                    // boxes beside it standing proud. Fixing the height lets
                    // the content centre inside it instead (2026-10-22).
                    height: kPrLabSelectorArrowSize,
                    // Glass compact — the neutral translucent treatment,
                    // swapped for the deleted box while it shows a deleted
                    // exercise: the set row's exact chrome, one recipe
                    // (2026-10-14).
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: _isDeleted(widget.activeIndex)
                        ? deletedBox()
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
                              _mark(widget.activeIndex, field: true),
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
              size: kPrLabSelectorArrowSize,
              iconSize: kPrLabSelectorArrowGlyph,
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
                      offset: const Offset(0, 4),
                      child: Container(
                        width: _fieldWidth,
                        constraints: const BoxConstraints(maxHeight: 260),
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
                        color: selected ? AppColors.primary : AppColors.muted,
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

  /// Arrow button — [size] is the full tap target ([kPrLabSelectorArrowSize]
  /// for the flanking field arrows, chevron 28×28 inside the popover rows).
  Widget _arrow(
    IconData icon,
    bool enabled,
    VoidCallback onTap, {
    Key? key,
    double size = 32,
    double iconSize = 18,
    String? semanticsLabel,
  }) {
    final button = GestureDetector(
      key: key,
      onTap: enabled ? onTap : () {},
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        // The glass recipe — the same chrome as every other pressable.
        decoration: enabled
            ? glassBox(AppColors.primary, radius: kPrLabSelectorArrowRadius)
            : BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(kPrLabSelectorArrowRadius),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
        child: Icon(
          icon,
          size: iconSize,
          color: enabled ? AppColors.primary : AppColors.muted,
        ),
      ),
    );

    if (semanticsLabel == null) return button;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: button,
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
            Text(
              'Add/Remove Exercises',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
