import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import 'container_styles.dart';

/// One tile within a [StatsRow].
class StatsTile {
  const StatsTile({
    required this.label,
    required this.value,
    this.accent = false,
    this.greyed = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool accent;

  /// Disabled look — label and value both muted. The planner's SETS/
  /// EXERCISES tiles are shown but greyed: planning has no live data.
  final bool greyed;

  final VoidCallback? onTap;
}

/// A border-contained row of [StatsTile]s — used for the stats bar on both
/// the session screen (4 tiles: Sets/PRs/Exercises/Avg Rest) and the
/// planned-workout screen (2 tiles: Sets/Exercises).
class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.tiles});

  final List<StatsTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: lambdaBox(ContainerTone.surface),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) Container(width: 1, color: AppColors.border),
            Expanded(child: _tileWidget(tiles[i])),
          ],
        ],
      ),
    );
  }

  Widget _tileWidget(StatsTile tile) {
    final content = Container(
      color: tile.accent ? AppColors.accentBg : AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        children: [
          Text(tile.label,
              textAlign: TextAlign.center,
              style: AppFonts.mono(
                  fontSize: 14, letterSpacing: 0.8, color: tile.accent ? AppColors.accent : AppColors.muted)),
          const SizedBox(height: 3),
          Text(tile.value,
              style: AppFonts.mono(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: tile.accent
                      ? AppColors.accent
                      : (tile.greyed ? AppColors.muted : AppColors.primary))),
        ],
      ),
    );
    if (tile.onTap == null) return content;
    return GestureDetector(onTap: tile.onTap, child: content);
  }
}
