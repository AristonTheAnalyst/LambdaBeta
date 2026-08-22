import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import 'exercise_tab_chip.dart';

/// The horizontally-scrollable exercise pill bar shared by the session
/// screen, the planner, and the past-session viewer — one implementation so
/// their UX stays 1:1.
///
/// Gestures: a plain horizontal drag scrolls the list; press-and-hold then
/// drag reorders (only when [onReorder] is set and there are more than 2
/// pills). A thin scrollbar strip below the pills fades in while scrolling
/// and fades out when idle.
class ExercisePillBar extends StatefulWidget {
  const ExercisePillBar({
    super.key,
    required this.labels,
    required this.keys,
    required this.activeIndex,
    required this.onTap,
    this.onReorder,
    this.onRemove,
    this.onAdd,
    this.prefixIcons,
  });

  final List<String> labels;

  /// Unique ids used as reorder keys — one per label.
  final List<String> keys;

  final int activeIndex;
  final ValueChanged<int> onTap;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(int index)? onRemove;
  final VoidCallback? onAdd;

  /// Optional leading icon per pill (e.g. the superset hexagon).
  final List<IconData?>? prefixIcons;

  @override
  State<ExercisePillBar> createState() => _ExercisePillBarState();
}

class _ExercisePillBarState extends State<ExercisePillBar> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _reorderable => widget.labels.length > 2 && widget.onReorder != null;

  Widget _pillItem(int i) {
    return SizedBox(
      key: ValueKey('ex-${widget.keys[i]}'),
      child: _reorderable
          ? ReorderableDelayedDragStartListener(index: i, child: _pill(i))
          : _pill(i),
    );
  }

  List<Widget> _pills() => [
    for (var i = 0; i < widget.labels.length; i++) _pillItem(i),
  ];

  Widget _pill(int i) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ExerciseTabChip(
        label: widget.labels[i],
        isActive: i == widget.activeIndex,
        prefixIcon: widget.prefixIcons != null && i < widget.prefixIcons!.length
            ? widget.prefixIcons![i]
            : null,
        onTap: () {
          // Switching exercises must first blur any focused set cell so its
          // typed value commits (cells auto-commit on focus loss).
          FocusManager.instance.primaryFocus?.unfocus();
          widget.onTap(i);
        },
        onRemove: i == widget.activeIndex && widget.onRemove != null
            ? () => widget.onRemove!(i)
            : null,
      ),
    );
  }

  /// The non-reorderable path with more pills than fit: left-aligned and
  /// scrollable.
  Widget _scrollablePills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollCtrl,
      child: Row(children: _pills()),
    );
  }

  /// Disables the theme's automatic scrollbar on the inner scrollable —
  /// otherwise it stacks a second indicator (and a second, conflicting drag
  /// surface) on top of the bar's own scrollbar below the pills.
  Widget _noAutoScrollbar(Widget scrollable) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: scrollable,
  );

  /// The pill list, feathered on the right edge so pills fade out before the
  /// "+" button instead of clipping hard against it.
  Widget _feathered(Widget pills) {
    return Stack(
      children: [
        pills,
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 14,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.bg.withValues(alpha: 0), AppColors.bg],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            // Pills (30) centered + scrollbar thumb (3) below + 4px breathing
            // room under the thumb. Kept tight so the page gaps above/below
            // the pills stay compact.
            height: 44,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Scrollbar(
                controller: _scrollCtrl,
                thickness: 3,
                radius: const Radius.circular(2),
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    height: 30,
                    child: _reorderable
                        ? _feathered(
                            _noAutoScrollbar(
                              // .builder instead of the children-based list:
                              // the children form hits Flutter's duplicate
                              // _ReorderableListViewChildGlobalKey bug when
                              // the list rebuilds mid-frame.
                              ReorderableListView.builder(
                                scrollDirection: Axis.horizontal,
                                scrollController: _scrollCtrl,
                                onReorderItem: (oldIndex, newIndex) =>
                                    widget.onReorder!(oldIndex, newIndex),
                                buildDefaultDragHandles: false,
                                proxyDecorator: (child, index, _) => Material(
                                  color: Colors.transparent,
                                  child: Opacity(opacity: 0.85, child: child),
                                ),
                                itemCount: widget.labels.length,
                                itemBuilder: (_, i) => _pillItem(i),
                              ),
                            ),
                          )
                        // 1-2 pills always fit — a plain Row stays out of the
                        // gesture arena so swiping over the bar still pages
                        // the session screens. More pills scroll instead.
                        : _feathered(
                            widget.labels.length > 2
                                ? _noAutoScrollbar(_scrollablePills())
                                : Row(children: _pills()),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.onAdd != null) ...[
          const SizedBox(width: 6),
          AddExerciseButton(onTap: widget.onAdd!),
        ],
      ],
    );
  }
}
