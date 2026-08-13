import 'package:flutter/material.dart';
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

  List<Widget> _pills() {
    return [
      for (var i = 0; i < widget.labels.length; i++)
        SizedBox(
          key: ValueKey('ex-${widget.keys[i]}'),
          child: _reorderable
              ? ReorderableDelayedDragStartListener(
                  index: i,
                  child: _pill(i),
                )
              : _pill(i),
        ),
    ];
  }

  Widget _pill(int i) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ExerciseTabChip(
        label: widget.labels[i],
        isActive: i == widget.activeIndex,
        prefixIcon: widget.prefixIcons != null && i < widget.prefixIcons!.length
            ? widget.prefixIcons![i]
            : null,
        onTap: () => widget.onTap(i),
        onRemove: widget.onRemove != null ? () => widget.onRemove!(i) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            // Extra 6px below the pills gives the scrollbar thumb its own
            // strip. The Scrollbar fades in while scrolling and fades out
            // when idle.
            height: 48,
            child: Scrollbar(
              controller: _scrollCtrl,
              thickness: 3,
              radius: const Radius.circular(2),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 42,
                  child: _reorderable
                      ? ReorderableListView(
                          scrollDirection: Axis.horizontal,
                          scrollController: _scrollCtrl,
                          onReorderItem: (oldIndex, newIndex) =>
                              widget.onReorder!(oldIndex, newIndex),
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, _) => Material(
                            color: Colors.transparent,
                            child: Opacity(opacity: 0.85, child: child),
                          ),
                          children: _pills(),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _scrollCtrl,
                          child: Row(children: _pills()),
                        ),
                ),
              ),
            ),
          ),
        ),
        if (widget.onAdd != null) AddExerciseButton(onTap: widget.onAdd!),
      ],
    );
  }
}
