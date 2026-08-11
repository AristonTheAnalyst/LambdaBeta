import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/workout_format.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/pr_engine.dart';

/// Training rep-bands for grouping the rep-max curve pills.
const _repBands = [
  (label: 'Strength', min: 1, max: 3),
  (label: 'Strength Endurance', min: 4, max: 6),
  (label: 'Hypertrophy', min: 7, max: 15),
  (label: 'Endurance', min: 16, max: null),
];

/// Sentinel value meaning "no filter" / "show all".
const _all = '__all__';

void showPrModal(BuildContext context, {required List<PrRecord> prs}) {
  // Only show explicit (non-propagated) PRs to the user — ascertained ones
  // exist for the statistics curve but aren't session achievements.
  final explicit = prs.where((p) => !p.isPropagated).toList();

  // ── Build the exercise / variation filter options from explicit PRs ──
  final exIds = <String>{}; // exerciseIds that have at least one PR
  final exName = <String, String>{}; // exerciseId -> display name
  final exVars = <String, Set<String?>>{}; // exerciseId -> {variationId, null}
  final exVarNames = <String, Map<String?, String>>{}; // exerciseId -> {varId -> name}

  for (final p in explicit) {
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
        prs: explicit,
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

  final List<PrRecord> prs;
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

  List<PrRecord> get _filtered {
    var out = widget.prs;
    if (_exFilter != _all) {
      out = out.where((p) => p.exerciseId == _exFilter).toList();
    }
    if (_varFilter != _all) {
      out = out.where((p) => p.variationId == _varFilter).toList();
    }
    return out;
  }

  bool _inBand(PrRecord p, ({String label, int min, int? max}) band) {
    if (p.targetReps == null) return false;
    if (p.targetReps! < band.min) return false;
    return band.max == null || p.targetReps! <= band.max!;
  }

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final repMax = <int, PrRecord>{};
    for (final p in filtered) {
      if (p.type == PrType.repMax &&
          p.targetReps != null &&
          kTrackedRepCounts.contains(p.targetReps!)) {
        repMax[p.targetReps!] = p;
      }
    }
    final weightMax = <num, PrRecord>{};
    for (final p in filtered) {
      if (p.type == PrType.weightMax && p.targetWeight != null) {
        weightMax[p.targetWeight!] = p;
      }
    }

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
          if (filtered.isEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('No PRs match the filter',
                style: AppFonts.ui(fontSize: 13, color: AppColors.muted)),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            // ── Rep-max pills ──
            if (repMax.isNotEmpty) ...[
              _SectionLabel(text: 'REP-MAX'),
              const SizedBox(height: AppSpacing.sm),
              for (final band in _repBands)
                _BandGroup(
                  band: band,
                  repMax: repMax,
                  inBand: _inBand,
                  fmt: _fmt,
                ),
            ],
            // ── Weight-max pills ──
            if (weightMax.isNotEmpty) ...[
              _SectionLabel(text: 'WEIGHT MAX'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: weightMax.entries
                    .map((e) =>
                        _Pill(label: '${_fmt(e.key)}kg X ${_fmt(e.value.reps)}'))
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ],
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
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(_label,
                  style: AppFonts.ui(
                      fontSize: 12,
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

// ── Band group ───────────────────────────────────────────────────────────────

class _BandGroup extends StatelessWidget {
  const _BandGroup({
    required this.band,
    required this.repMax,
    required this.inBand,
    required this.fmt,
  });

  final ({String label, int min, int? max}) band;
  final Map<int, PrRecord> repMax;
  final bool Function(PrRecord, ({String label, int min, int? max})) inBand;
  final String Function(num) fmt;

  String get _range =>
      band.max == null ? '${band.min}+RM' : '${band.min}-${band.max}RM';

  @override
  Widget build(BuildContext context) {
    final entries = repMax.entries
        .where((e) => inBand(e.value, band))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${band.label} · $_range',
                style: AppFonts.mono(
                    fontSize: 10, letterSpacing: 0.6, color: AppColors.muted)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entries
                .map((e) => _Pill(label: '${e.key}RM - ${fmt(e.value.weight)}kg'))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Shared pill chip ─────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: AppFonts.mono(fontSize: 11, color: AppColors.accent)),
    );
  }
}

// ── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: AppFonts.mono(
              fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
    );
  }
}
