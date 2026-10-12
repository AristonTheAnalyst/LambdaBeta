import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';

/// How a review's two sides disagree about an exercise, read off its name: a
/// green **plus** for one the comparison base did not hold (added since it),
/// a red **minus** for one it did hold and the side on screen does not
/// (dropped).
///
/// The mark says something about the COMPARISON, not about the workout —
/// nothing is stored, and where the two sides do not meet the same exercise
/// wears the plus from one side of the eye and the minus from the other. It
/// appears nowhere else: a live session, a log, a plan on its own has no
/// second reading to be a change against.
enum ExerciseMark {
  added(Icons.add_circle),
  removed(Icons.remove_circle);

  const ExerciseMark(this.icon);

  /// The glyph the name wears — the plus or minus inside a disc, because a
  /// bare stroke at this size reads as a hyphen, or as a smudge, against the
  /// name it is about (2026-10-12). Colour resolves at draw time — the tokens
  /// are getters over the live theme, so no enum constant can hold one — and
  /// is always [AppColors.success] for [added], [AppColors.danger] for
  /// [removed].
  final IconData icon;
}

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
  });

  /// Display names, in order.
  final List<String> exercises;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// One mark per name, parallel to [exercises]. A null entry, a list that
  /// stops short, or no list at all leaves that name bare — an unmarked name
  /// draws nothing, not even the gap its mark would take. Only a review fills
  /// these.
  final List<ExerciseMark?> marks;

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

  /// The glyph a marked name wears, riding directly after it: the name
  /// ellipsizes to its left, so a long one narrows rather than pushing its
  /// mark out of the field. An unmarked name draws nothing at all.
  Widget _mark(int i) {
    final mark = i < widget.marks.length ? widget.marks[i] : null;
    if (mark == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        mark.icon,
        size: 14,
        color: mark == ExerciseMark.added
            ? AppColors.success
            : AppColors.danger,
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
            // opening the popover. Greyed at the ends of the list.
            _arrow(
              Icons.keyboard_arrow_left,
              widget.exercises.length > 1 && widget.activeIndex > 0,
              () => widget.onSelect(widget.activeIndex - 1),
              key: const ValueKey('exercise-selector-prev'),
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
                    // Glass compact — the neutral translucent treatment.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
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
              Icons.keyboard_arrow_right,
              widget.exercises.length > 1 &&
                  widget.activeIndex < widget.exercises.length - 1,
              () => widget.onSelect(widget.activeIndex + 1),
              key: const ValueKey('exercise-selector-next'),
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
                        decoration: lambdaBox(ContainerTone.surface, radius: AppRadius.md),
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
        decoration: BoxDecoration(
          // The selected exercise shows with the neutral glass highlight.
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
            ),
            const SizedBox(width: 2),
            _arrow(
              Icons.keyboard_arrow_down,
              widget.onMove != null && i < widget.exercises.length - 1,
              () => widget.onMove!(i, 1),
              size: 28,
              iconSize: 15,
            ),
          ],
        ),
      ),
    );
  }

  /// Arrow button — [size] is the full tap target (icon-button 32×32 for the
  /// flanking field arrows, chevron 28×28 inside the popover rows).
  Widget _arrow(
    IconData icon,
    bool enabled,
    VoidCallback onTap, {
    Key? key,
    double size = 32,
    double iconSize = 18,
  }) {
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : () {},
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        // The glass recipe — the same chrome as every other pressable.
        decoration: enabled
            ? glassBox(AppColors.primary, radius: 6)
            : BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
        child: Icon(
          icon,
          size: iconSize,
          color: enabled ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }

  /// Pinned at the bottom of the popover — the caller opens its own
  /// exercise picker, which is where exercises are both added and removed.
  /// When [widget.onAdd] is null the row stays visible but renders greyed and
  /// inert, so read-only contexts keep the popover's shape without a dead
  /// action.
  Widget _addRow() {
    final enabled = widget.onAdd != null;
    final color = enabled ? AppColors.primary : AppColors.muted.withValues(alpha: 0.4);
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

