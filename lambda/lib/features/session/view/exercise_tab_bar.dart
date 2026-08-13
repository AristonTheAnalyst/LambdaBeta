import 'package:flutter/material.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/exercise_tab_chip.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'add_exercise_modal.dart';

class ExerciseTabBar extends StatelessWidget {
  const ExerciseTabBar({super.key, required this.vm, required this.onRemove});

  final SessionViewModel vm;
  final void Function(int index) onRemove;

  String _label(SessionExerciseSlot slot, int supersetNumber) {
    if (slot.type == SessionSlotType.single) {
      return toProperCase(vm.exerciseDisplayName(slot.exerciseIds.first));
    }
    return 'Superset $supersetNumber';
  }

  @override
  Widget build(BuildContext context) {
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
              child: vm.exerciseSlots.length > 2
                  ? SizedBox(
                      height: 42,
                      child: ReorderableListView(
                        scrollDirection: Axis.horizontal,
                        onReorderItem: (oldIndex, newIndex) => vm.reorderExercises(oldIndex, newIndex),
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, _) => Material(
                          color: Colors.transparent,
                          child: Opacity(opacity: 0.85, child: child),
                        ),
                        children: [
                          for (var i = 0; i < vm.exerciseSlots.length; i++)
                            SizedBox(
                              key: ValueKey('ex-${vm.exerciseSlots[i].id}'),
                              child: ReorderableDragStartListener(
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
                                    onRemove: () => onRemove(i),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                              onRemove: () => onRemove(i),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
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
