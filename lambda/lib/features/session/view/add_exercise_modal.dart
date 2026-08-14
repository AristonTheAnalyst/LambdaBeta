import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';

void showAddExerciseModal(BuildContext context, {required SessionViewModel vm}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _AddExerciseModalContent(vm: vm),
  );
}

/// Single-exercise add modal — search the library (most recently used
/// first) or create a new exercise inline.
///
/// Supersets were retired from the frontend UX (2026-08-14, see CLAUDE.md):
/// the schema and the VM's superset data-model support remain dormant for
/// compatibility with existing data, but no UI creates supersets anymore.
class _AddExerciseModalContent extends StatefulWidget {
  const _AddExerciseModalContent({required this.vm});

  final SessionViewModel vm;

  @override
  State<_AddExerciseModalContent> createState() => _AddExerciseModalContentState();
}

class _AddExerciseModalContentState extends State<_AddExerciseModalContent> {
  String _query = '';

  List<MapEntry<String, String>> get _filtered {
    final results = widget.vm.exercises
        .where((e) => toProperCase(e.name).toLowerCase().contains(_query.toLowerCase()))
        .map((e) => MapEntry(e.exerciseId, toProperCase(e.name)))
        .toList();
    // Most recently used first (unused last, then name).
    results.sort((a, b) {
      final da = widget.vm.lastUsedByExercise[a.key];
      final db = widget.vm.lastUsedByExercise[b.key];
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });
    return results;
  }

  bool get _canCreate =>
      _query.trim().length > 1 &&
      !widget.vm.exercises.any((e) => e.name.toLowerCase() == _query.trim().toLowerCase());

  void _pickSingle(String exerciseId) {
    widget.vm.addExerciseSlot(exerciseId);
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _createNew() async {
    final id = await widget.vm.submitNewExercise(_query);
    if (id == null || !mounted) return;
    _pickSingle(id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Choose exercise',
                      style: AppFonts.ui(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _searchStep(),
          ],
        ),
      ),
    );
  }

  Widget _searchStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
          decoration: InputDecoration(
            hintText: 'Search exercises…',
            hintStyle: AppFonts.ui(color: AppColors.muted),
            prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListenableBuilder(
            listenable: widget.vm,
            builder: (context, _) => ListView(
              shrinkWrap: true,
              children: [
                ..._filtered.map((e) => _resultRow(e.value, () => _pickSingle(e.key))),
                if (_canCreate)
                  _resultRow('+ Create "${_query.trim()}"', widget.vm.newExCreating ? null : _createNew,
                      accent: true),
                if (_filtered.isEmpty && !_canCreate && _query.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                        child:
                            Text('No exercises found', style: AppFonts.ui(fontSize: 13, color: AppColors.muted))),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(String label, VoidCallback? onTap, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: accent ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
                style: accent ? BorderStyle.solid : BorderStyle.solid),
          ),
          child: Text(label,
              style: AppFonts.ui(
                  fontSize: 14,
                  fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                  color: accent ? AppColors.primary : AppColors.primary)),
        ),
      ),
    );
  }
}
