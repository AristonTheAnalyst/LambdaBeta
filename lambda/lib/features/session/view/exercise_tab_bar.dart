import 'package:flutter/material.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/exercise_tab_chip.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'add_exercise_modal.dart';

class ExerciseTabBar extends StatefulWidget {
  const ExerciseTabBar({super.key, required this.vm, required this.onRemove});

  final SessionViewModel vm;
  final void Function(int index) onRemove;

  @override
  State<ExerciseTabBar> createState() => _ExerciseTabBarState();
}

class _ExerciseTabBarState extends State<ExerciseTabBar> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _label(SessionExerciseSlot slot, int supersetNumber) {
    if (slot.type == SessionSlotType.single) {
      return toProperCase(widget.vm.exerciseDisplayName(slot.exerciseIds.first));
    }
    return 'Superset $supersetNumber';
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        var supersetCount = 0;
        final supersetNumbers = vm.exerciseSlots
            .map((s) => s.type == SessionSlotType.superset ? ++supersetCount : 0)
            .toList();
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                // Extra 6px below the pills gives the scrollbar thumb its own
                // strip. The Scrollbar's default behavior is exactly what we
                // want: it fades in while scrolling and fades out when idle.
                height: 48,
                child: Scrollbar(
                  controller: _scrollCtrl,
                  thickness: 3,
                  radius: const Radius.circular(2),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: 42,
                      child: vm.exerciseSlots.length > 2
                          ? ReorderableListView(
                              scrollDirection: Axis.horizontal,
                              scrollController: _scrollCtrl,
                              onReorderItem: (oldIndex, newIndex) =>
                                  vm.reorderExercises(oldIndex, newIndex),
                              buildDefaultDragHandles: false,
                              proxyDecorator: (child, index, _) => Material(
                                color: Colors.transparent,
                                child: Opacity(opacity: 0.85, child: child),
                              ),
                              children: [
                                for (var i = 0; i < vm.exerciseSlots.length; i++)
                                  SizedBox(
                                    key: ValueKey('ex-${vm.exerciseSlots[i].id}'),
                                    // Delayed (press-and-hold) drag start: a
                                    // plain horizontal drag scrolls the list,
                                    // while a squash-and-drag reorders.
                                    child: ReorderableDelayedDragStartListener(
                                      index: i,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ExerciseTabChip(
                                          label: _label(vm.exerciseSlots[i], supersetNumbers[i]),
                                          isActive: i == vm.activeSlotIndex,
                                          prefixIcon: vm.exerciseSlots[i].type == SessionSlotType.superset
                                              ? Icons.hexagon_outlined
                                              : null,
                                          onTap: () => vm.tapTab(i),
                                          onRemove: () => widget.onRemove(i),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _scrollCtrl,
                              child: Row(
                                children: [
                                  for (var i = 0; i < vm.exerciseSlots.length; i++) ...[
                                    ExerciseTabChip(
                                      label: _label(vm.exerciseSlots[i], supersetNumbers[i]),
                                      isActive: i == vm.activeSlotIndex,
                                      prefixIcon: vm.exerciseSlots[i].type == SessionSlotType.superset
                                          ? Icons.hexagon_outlined
                                          : null,
                                      onTap: () => vm.tapTab(i),
                                      onRemove: () => widget.onRemove(i),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            AddExerciseButton(onTap: () => showAddExerciseModal(context, vm: vm)),
          ],
        );
      },
    );
  }
}
