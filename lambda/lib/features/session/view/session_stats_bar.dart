import 'package:flutter/material.dart';
import '../../../shared/widgets/stats_row.dart';
import '../viewmodel/session_viewmodel.dart';
import 'pr_modal.dart';

/// Sets / PRs / Exercises — always visible atop the active workout.
/// The PR tile is tappable once there's at least one PR.
class SessionStatsBar extends StatelessWidget {
  const SessionStatsBar({super.key, required this.vm});

  final SessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final prs = vm.totalPRsThisSession;
        return StatsRow(tiles: [
          StatsTile(label: 'SETS', value: '${vm.sets.length}'),
          StatsTile(
            label: 'PRS',
            value: '$prs',
            accent: prs > 0,
            onTap: prs > 0 ? () => showPrModal(context, prs: vm.prsThisSession) : null,
          ),
          StatsTile(label: 'EXERCISES', value: '${vm.distinctExerciseCount}'),
        ]);
      },
    );
  }
}
