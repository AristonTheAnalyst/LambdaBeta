import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/glass_button.dart';
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

enum _Step { choose, single, superset }

class _AddExerciseModalContent extends StatefulWidget {
  const _AddExerciseModalContent({required this.vm});

  final SessionViewModel vm;

  @override
  State<_AddExerciseModalContent> createState() => _AddExerciseModalContentState();
}

class _AddExerciseModalContentState extends State<_AddExerciseModalContent> {
  _Step _step = _Step.choose;
  String _query = '';
  final List<String> _selectedIds = [];

  bool get _isSuperset => _step == _Step.superset;

  List<MapEntry<String, String>> get _filtered {
    final already = _selectedIds.toSet();
    final results = widget.vm.exercises
        .where((e) => !already.contains(e.exerciseId))
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

  void _addToSuperset(String exerciseId) {
    setState(() {
      _selectedIds.add(exerciseId);
      _query = '';
    });
  }

  Future<void> _createNew() async {
    final id = await widget.vm.submitNewExercise(_query);
    if (id == null || !mounted) return;
    if (_step == _Step.single) {
      _pickSingle(id);
    } else {
      _addToSuperset(id);
    }
  }

  void _confirmSuperset() {
    if (_selectedIds.length < 2) return;
    widget.vm.addSupersetSlot(_selectedIds);
    Navigator.of(context, rootNavigator: true).pop();
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
                  child: Text(
                    _step == _Step.choose
                        ? 'Add to workout'
                        : _step == _Step.single
                            ? 'Choose exercise'
                            : 'Build superset',
                    style: AppFonts.ui(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_step == _Step.choose) _chooseStep(),
            if (_step != _Step.choose) _searchStep(),
          ],
        ),
      ),
    );
  }

  Widget _chooseStep() {
    return Row(
      children: [
        Expanded(
          child: _choiceCard(
            icon: Icons.fitness_center,
            label: 'Set',
            sub: 'Single exercise',
            onTap: () => setState(() => _step = _Step.single),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _choiceCard(
            icon: Icons.hexagon_outlined,
            label: 'Superset',
            sub: 'Multiple exercises',
            onTap: () => setState(() => _step = _Step.superset),
          ),
        ),
      ],
    );
  }

  Widget _choiceCard(
      {required IconData icon, required String label, required String sub, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.accent, size: 22),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: AppFonts.ui(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: 2),
            Text(sub, style: AppFonts.ui(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _searchStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSuperset && _selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedIds.map((id) {
                final name = toProperCase(widget.vm.exerciseDetailMap[id]?.name ?? '');
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          style:
                              AppFonts.ui(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _selectedIds.remove(id)),
                        child: Icon(Icons.close, size: 12, color: AppColors.accent),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        TextField(
          autofocus: true,
          style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
          decoration: InputDecoration(
            hintText: _isSuperset && _selectedIds.isNotEmpty ? 'Add another exercise…' : 'Search exercises…',
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
                ..._filtered.map((e) => _resultRow(e.value, () {
                      if (_isSuperset) {
                        _addToSuperset(e.key);
                      } else {
                        _pickSingle(e.key);
                      }
                    })),
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
        if (_isSuperset && _selectedIds.length >= 2) ...[
          const SizedBox(height: AppSpacing.md),
          GlassButton(
              label: 'Create Superset (${_selectedIds.length} exercises)',
              solid: true,
              onPressed: _confirmSuperset),
        ],
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
                color: accent ? AppColors.accent.withValues(alpha: 0.35) : AppColors.border,
                style: accent ? BorderStyle.solid : BorderStyle.solid),
          ),
          child: Text(label,
              style: AppFonts.ui(
                  fontSize: 14,
                  fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                  color: accent ? AppColors.accent : AppColors.primary)),
        ),
      ),
    );
  }
}
