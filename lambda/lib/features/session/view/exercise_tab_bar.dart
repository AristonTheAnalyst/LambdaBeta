import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/utils/workout_format.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'add_exercise_modal.dart';

class ExerciseTabBar extends StatelessWidget {
  const ExerciseTabBar({super.key, required this.vm});

  final SessionViewModel vm;

  String _label(SessionExerciseSlot slot, int supersetNumber) {
    if (slot.type == SessionSlotType.single) {
      final name = vm.exerciseDetailMap[slot.exerciseIds.first]?.name ?? '';
      return toProperCase(name);
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
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < vm.exerciseSlots.length; i++) ...[
                      _TabChip(
                        label: _label(vm.exerciseSlots[i], supersetNumbers[i]),
                        isActive: i == vm.activeSlotIndex,
                        isSuperset: vm.exerciseSlots[i].type == SessionSlotType.superset,
                        loggedCount: vm.sets
                            .where((s) => s.exerciseId == vm.exerciseSlots[i].activeExerciseId)
                            .length,
                        onTap: () => vm.tapTab(i),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => showAddExerciseModal(context, vm: vm),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.add, size: 16, color: AppColors.muted),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.isActive,
    required this.isSuperset,
    required this.loggedCount,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool isSuperset;
  final int loggedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentBg : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSuperset)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.hexagon_outlined, size: 11, color: AppColors.accent),
              ),
            Text(label,
                style: AppFonts.ui(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? AppColors.accent : AppColors.primary)),
            if (!isSuperset && loggedCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$loggedCount', style: AppFonts.mono(fontSize: 10, color: AppColors.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
