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
    this.onTap,
  });

  final String label;
  final String value;
  final bool accent;

  final VoidCallback? onTap;
}

/// A border-contained row of [StatsTile]s — used for the stats bar on both
/// the session screen (4 tiles: Sets/PRs/Exercises/Avg Rest) and the
/// planned-workout screen (2 tiles: Sets/Exercises).
class StatsRow extends StatelessWidget {
  const StatsRow({
    super.key,
    required this.tiles,
    this.inline = false,
    this.tone = ContainerTone.surface,
  });

  final List<StatsTile> tiles;

  /// Each tile reads on one line — label, then its number — instead of the
  /// label over the value. How the session's own bar reads its tiles, and
  /// what a short row has the width for: the planner's two tiles wear it;
  /// four do not.
  final bool inline;

  /// The row's own container — the fill and rim it sits in. Null drops it:
  /// tiles and dividers only, for a row that already has somewhere to sit.
  /// The planner's counts ride in a floating glass pill, and a box inside a
  /// glass reads as two containers.
  ///
  /// A row with no container paints no tile fill either, and every word in it
  /// reads at full strength: there is no surface behind the row for a label
  /// to sit back against.
  final ContainerTone? tone;

  @override
  Widget build(BuildContext context) {
    final tone = this.tone;
    return Container(
      decoration: tone == null ? null : lambdaBox(tone),
      // The clip is what rounds the tiles' fills to the container's corners.
      // With no container there is nothing to round them to — and a clip
      // without a decoration is not a container at all.
      clipBehavior: tone == null ? Clip.none : Clip.antiAlias,
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
    final tone = this.tone;
    final label = Text(
        tile.label,
        textAlign: TextAlign.center,
        style: AppFonts.mono(
            // Inline, a label and its number are one reading, so they hold one
            // size — the label steps up to the number's, never the number down
            // to the label's. Stacked, the two lines keep their own.
            fontSize: inline ? 17 : 14,
            letterSpacing: 0.8,
            color: tile.accent
                ? AppColors.accent
                : (tone == null ? AppColors.primary : AppColors.muted)));
    final value = Text(
        tile.value,
        style: AppFonts.mono(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: tile.accent ? AppColors.accent : AppColors.primary));
    final content = Container(
      // A tile's fill belongs to the row's container: with no container of
      // its own, the tile paints nothing and whatever the row is standing on
      // shows through.
      color: tile.accent
          ? AppColors.accentBg
          : (tone == null ? null : AppColors.surface),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: inline
          // A label and its number are one reading, so they sit on one line —
          // baselined, not centred, because two type sizes centred against
          // each other float.
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                label,
                const SizedBox(width: 6),
                value,
              ],
            )
          : Column(
              children: [
                label,
                const SizedBox(height: 3),
                value,
              ],
            ),
    );
    if (tile.onTap == null) return content;
    return GestureDetector(onTap: tile.onTap, child: content);
  }
}
