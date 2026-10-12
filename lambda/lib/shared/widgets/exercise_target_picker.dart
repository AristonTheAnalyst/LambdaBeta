import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';
import '../../data/models/custom_variation.dart';
import '../../data/models/exercise_detail.dart';
import 'container_styles.dart';
import 'dropdown_select.dart';
import 'glass_button.dart';
import 'lambda_search_field.dart';

/// What [ExerciseTargetPicker] produced — an exercise, optionally a variation,
/// and the weight × reps being chased.
///
/// A value object rather than four positional arguments: the variation is
/// optional and sits between two required values, and a callback whose third
/// parameter can mean either "no variation" or "the caller forgot" is a bug
/// waiting to be written.
class ExerciseTarget {
  const ExerciseTarget({
    required this.exerciseId,
    required this.exerciseName,
    this.variationId,
    this.weight,
    this.reps,
  });

  final String exerciseId;

  /// The display name, resolved from the dims by the caller that built the
  /// map. Carried so a goal can name its lift without a second lookup.
  final String exerciseName;

  /// NULL = the exercise performed with no variation — a plain bench set, not
  /// any bench set. Its own scope, the same way the PR frontier keys one.
  final String? variationId;

  final num? weight;
  final int? reps;
}

/// Picks an exercise, a variation and a target, in one inline control.
///
/// Extracted from the program's goals panel, where it was the only way to add a
/// target. Three surfaces now ask the same question — a program's goals, a
/// block's goals, and a review-time edit — and they must ask it identically, or
/// the same lift ends up described two different ways in the same program.
///
/// Collapsed it is one tappable line; expanded it is search → variation →
/// weight × reps → Add, which is the order the decision is actually made in.
class ExerciseTargetPicker extends StatefulWidget {
  const ExerciseTargetPicker({
    super.key,
    required this.detailMap,
    required this.onAdd,
    this.variations = const [],
    this.collapsedLabel = 'Add a PR target…',
  });

  /// Every active exercise, by id. The picker searches it; it does not load it.
  final Map<String, ExerciseDetail> detailMap;

  /// Variations offered on the selected exercise. Empty hides the control, so
  /// a caller with no variation library yet renders exactly the old picker.
  final List<CustomVariation> variations;

  final void Function(ExerciseTarget target) onAdd;

  final String collapsedLabel;

  @override
  State<ExerciseTargetPicker> createState() => _ExerciseTargetPickerState();
}

class _ExerciseTargetPickerState extends State<ExerciseTargetPicker> {
  bool _expanded = false;
  String _query = '';
  String? _selectedExerciseId;
  String? _variationId;
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> get _filtered {
    final detailMap = widget.detailMap;
    if (detailMap.isEmpty) return [];
    final results = detailMap.entries
        .where((e) {
          final name = e.value.name;
          return _query.isEmpty ||
              toProperCase(name).toLowerCase().contains(_query.toLowerCase());
        })
        .map((e) => MapEntry(e.key, toProperCase(e.value.name)))
        .toList();
    results.sort(
      (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
    );
    return results;
  }

  void _collapse() => setState(() {
        _expanded = false;
        _query = '';
        _selectedExerciseId = null;
        _variationId = null;
        _weightCtrl.clear();
        _repsCtrl.clear();
      });

  void _add() {
    final id = _selectedExerciseId;
    if (id == null) return;
    final detail = widget.detailMap[id];
    widget.onAdd(
      ExerciseTarget(
        exerciseId: id,
        exerciseName: toProperCase(detail?.name ?? ''),
        variationId: _variationId,
        weight: double.tryParse(_weightCtrl.text.trim()),
        reps: int.tryParse(_repsCtrl.text.trim()),
      ),
    );
    _collapse();
  }

  /// Options are rebuilt from the live variation list each build, so an
  /// archived variation simply stops being offered — a goal already naming one
  /// still reads, because its id is what was stored.
  ///
  /// Alphabetical, unlike the set row's picker: that one sorts by last used
  /// because it is picking what you just did, and here nothing was just done.
  List<DropdownOption<String?>> get _variationOptions {
    final sorted = [
      for (final v in widget.variations)
        if (!v.isArchived) v,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      const DropdownOption(label: 'No variation', value: null),
      for (final v in sorted)
        DropdownOption(label: v.name, value: v.variationId),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expanded = true),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                widget.collapsedLabel,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LambdaSearchField(
          autofocus: true,
          showIcon: true,
          hint: 'Search exercises…',
          suffix: GestureDetector(
            onTap: _collapse,
            child: Icon(Icons.close, size: 16, color: AppColors.muted),
          ),
          onChanged: (v) => setState(() {
            _query = v;
            _selectedExerciseId = null;
          }),
        ),
        if (_selectedExerciseId == null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView(
              shrinkWrap: true,
              children: _filtered
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedExerciseId = e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          // Pressable picker rows — the glass recipe.
                          decoration: glassBox(AppColors.primary),
                          child: Text(
                            e.value,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (_selectedExerciseId != null) ...[
          const SizedBox(height: 8),
          Text(
            toProperCase(widget.detailMap[_selectedExerciseId!]?.name ?? ''),
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          if (widget.variations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownSelect<String?>(
                    options: _variationOptions,
                    value: _variationId,
                    placeholder: 'No variation',
                    onChange: (v) => setState(() => _variationId = v),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _weightCtrl,
                  hint: 'kg',
                  decimal: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '×',
                  style: AppFonts.ui(fontSize: 14, color: AppColors.muted),
                ),
              ),
              Expanded(
                child: _NumberField(controller: _repsCtrl, hint: 'reps'),
              ),
              const SizedBox(width: 6),
              GlassButton(label: 'Add', compact: true, onPressed: _add),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

/// The weight and reps cells — monospaced and numeric-only, the same pair the
/// set rows use, because a target and a logged value are the same two numbers.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.hint,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: [
        if (decimal)
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      style: AppFonts.mono(fontSize: 14, color: AppColors.primary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppFonts.mono(color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

/// A goal's one-line target description: "Bench — 100 kg × 1".
///
/// Shared so the goal list, the block editor and the review sheet describe a
/// target identically — the same reason [ExerciseTargetPicker] exists.
String goalTargetLabel(String exerciseName, num? weight, int? reps) {
  final target = goalTargetValue(weight, reps);
  return target.isEmpty ? exerciseName : '$exerciseName — $target';
}

/// The target alone — "100 kg × 1", empty when neither number was recorded —
/// without the exercise's name.
///
/// For the surfaces that draw the name and the target as two elements rather
/// than glue them into one string with a dash: the review pickers' rows align
/// the values in their own column (2026-10-10).
String goalTargetValue(num? weight, int? reps) {
  final parts = <String>[];
  if (weight != null) parts.add('${_fmt(weight)} kg');
  if (reps != null) parts.add('$reps rep${reps == 1 ? '' : 's'}');
  return parts.join(' × ');
}

String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';
