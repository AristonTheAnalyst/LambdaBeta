import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/pr_engine.dart';

/// Sentinel value meaning "no filter" / "show all".
const _all = '__all__';

/// Bottom sheet of a session's PR events — one row per frontier-extending
/// set with its before-facts. (Curves and per-axis progressions are insight
/// lenses; this sheet is the session's plain achievement list.)
void showPrModal(BuildContext context, {required List<PrEvent> prs}) {
  // ── Build the exercise / variation filter options from the events ──
  final exIds = <String>{}; // exerciseIds that have at least one PR
  final exName = <String, String>{}; // exerciseId -> display name
  final exVars = <String, Set<String?>>{}; // exerciseId -> {variationId, null}
  final exVarNames = <String, Map<String?, String>>{}; // exerciseId -> {varId -> name}

  for (final p in prs) {
    exIds.add(p.exerciseId);
    exName[p.exerciseId] = toProperCase(p.exerciseName ?? p.exerciseId);
    exVars.putIfAbsent(p.exerciseId, () => {});
    exVars[p.exerciseId]!.add(p.variationId);
    exVarNames.putIfAbsent(p.exerciseId, () => {});
    exVarNames[p.exerciseId]![p.variationId] =
        p.variationName != null ? toProperCase(p.variationName!) : '';
  }

  final sortedExIds = exIds.toList()
    ..sort((a, b) => (exName[a] ?? a).compareTo(exName[b] ?? b));

  showLambdaModal(
    context,
    fitContent: true,
    child: SafeArea(
      child: _PrSheet(
        prs: prs,
        sortedExIds: sortedExIds,
        exName: exName,
        exVars: exVars,
        exVarNames: exVarNames,
      ),
    ),
  );
}

class _PrSheet extends StatefulWidget {
  const _PrSheet({
    required this.prs,
    required this.sortedExIds,
    required this.exName,
    required this.exVars,
    required this.exVarNames,
  });

  final List<PrEvent> prs;
  final List<String> sortedExIds;
  final Map<String, String> exName;
  final Map<String, Set<String?>> exVars;
  final Map<String, Map<String?, String>> exVarNames;

  @override
  State<_PrSheet> createState() => _PrSheetState();
}

class _PrSheetState extends State<_PrSheet> {
  String? _exFilter = _all; // exerciseId, or _all
  String? _varFilter = _all; // variationId, null (no variation), or _all

  List<PrEvent> get _filtered {
    var out = widget.prs;
    if (_exFilter != _all) {
      out = out.where((p) => p.exerciseId == _exFilter).toList();
    }
    if (_varFilter != _all) {
      out = out.where((p) => p.variationId == _varFilter).toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    // Rebuild variation list when exercise filter changes.
    final varOptions = <String?>[];
    if (_exFilter != _all) {
      final vars = widget.exVars[_exFilter];
      if (vars != null) {
        // Sort: explicit variations alphabetically, then "no variation" last.
        final named = vars.where((v) => v != null).toList()
          ..sort((a, b) {
            final na =
                widget.exVarNames[_exFilter]?[a] ?? a ?? '';
            final nb =
                widget.exVarNames[_exFilter]?[b] ?? b ?? '';
            return na.compareTo(nb);
          });
        final hasNull = vars.contains(null);
        varOptions.addAll(named);
        if (hasNull) varOptions.add(null);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header + filters ──
          Row(
            children: [
              Expanded(
                child: Text('PRs Achieved',
                    style: AppFonts.ui(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Exercise + variation filters, side by side.
          Row(
            children: [
              Expanded(
                child: _FilterDropdown(
                  value: _exFilter,
                  items: [
                    const _FilterItem(value: _all, label: 'All exercises'),
                    for (final id in widget.sortedExIds)
                      _FilterItem(value: id, label: widget.exName[id] ?? id),
                  ],
                  onChanged: (v) => setState(() {
                    _exFilter = v;
                    _varFilter = _all;
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _FilterDropdown(
                  value: _varFilter,
                  items: [
                    const _FilterItem(value: _all, label: 'All variations'),
                    if (_exFilter != _all)
                      for (final v in varOptions)
                        _FilterItem(
                          value: v,
                          label: v == null
                              ? 'No variation'
                              : (widget.exVarNames[_exFilter]?[v] ?? v),
                        ),
                  ],
                  onChanged: (v) => setState(() => _varFilter = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (filtered.isEmpty)
            Text('No PRs match the filter',
                style: AppFonts.ui(fontSize: 13, color: AppColors.muted))
          else
            for (final e in filtered) PrEventRow(e),
        ],
      ),
    );
  }

}

// ── Filter dropdown ──────────────────────────────────────────────────────────

class _FilterItem {
  const _FilterItem({required this.value, required this.label});
  final String? value;
  final String label;
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String? value;
  final List<_FilterItem> items;
  final ValueChanged<String?> onChanged;

  String get _label =>
      items.firstWhere((i) => i.value == value, orElse: () => items.first).label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      initialValue: value,
      onSelected: onChanged,
      offset: const Offset(0, 40),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: glassBox(AppColors.primary, radius: AppRadius.md),
        child: Row(
          children: [
            Expanded(
              child: Text(_label,
                  style: AppFonts.ui(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        for (final item in items)
          PopupMenuItem<String?>(
            value: item.value,
            child: Text(item.label,
                style: AppFonts.ui(
                    fontSize: 13,
                    fontWeight: item.value == value ? FontWeight.w700 : FontWeight.w400,
                    color: AppColors.primary)),
          ),
      ],
    );
  }
}
