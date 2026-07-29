import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../viewmodel/session_viewmodel.dart';
import 'pr_modal.dart';

/// Sets / PRs / Exercises / Avg Rest — always visible atop the active
/// workout. The PR tile is tappable once there's at least one PR.
class SessionStatsBar extends StatelessWidget {
  const SessionStatsBar({super.key, required this.vm});

  final SessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final prs = vm.totalPRsThisSession;
        final avgRest = vm.avgRestSeconds;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(child: _tile(label: 'SETS', value: '${vm.sets.length}')),
              _divider(),
              Expanded(
                child: _tile(
                  label: 'PRS',
                  value: '$prs',
                  accent: prs > 0,
                  onTap: prs > 0 ? () => showPrModal(context, vm: vm) : null,
                ),
              ),
              _divider(),
              Expanded(child: _tile(label: 'EXERCISES', value: '${vm.distinctExerciseCount}')),
              _divider(),
              Expanded(
                child: _tile(
                  label: 'AVG REST',
                  value: avgRest != null
                      ? '${avgRest ~/ 60}:${(avgRest.round() % 60).toString().padLeft(2, '0')}'
                      : '—',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _divider() => Container(width: 1, color: AppColors.border);

  Widget _tile({required String label, required String value, bool accent = false, VoidCallback? onTap}) {
    final content = Container(
      color: accent ? AppColors.accentBg : AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: AppFonts.mono(
                  fontSize: 8, letterSpacing: 0.8, color: accent ? AppColors.accent : AppColors.muted)),
          const SizedBox(height: 3),
          Text(value,
              style: AppFonts.mono(
                  fontSize: 17, fontWeight: FontWeight.w500, color: accent ? AppColors.accent : AppColors.primary)),
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
