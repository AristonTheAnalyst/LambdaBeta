import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/powersync/database.dart' as ps;
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../shared/widgets/page_header.dart';

/// Raw ground-truth dump of `fact_lesson` plus the pending PowerSync upload
/// queue — bypasses every viewmodel/UI layer so we can see exactly how many
/// lessons the DB actually holds for a user, and whether uploads are stuck.
class LessonDebugScreen extends StatefulWidget {
  const LessonDebugScreen({super.key});

  @override
  State<LessonDebugScreen> createState() => _LessonDebugScreenState();
}

class _LessonDebugScreenState extends State<LessonDebugScreen> {
  List<Map<String, dynamic>> _rows = const [];
  List<Map<String, dynamic>> _crud = const [];
  bool _loading = true;
  String? _error;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ps.db.getAll(
        '''
        SELECT l.lesson_id, l.custom_exercise_id, l.lesson_text, l.pinned,
               l.is_archived, l.lesson_created_date, e.exercise_name
        FROM dim_lesson l
        LEFT JOIN dim_exercise e ON e.custom_exercise_id = l.custom_exercise_id
        WHERE l.user_id = ?
        ORDER BY l.lesson_created_date DESC
        ''',
        [_userId],
      );
      final crud = await ps.db.getAll(
        'SELECT id, data, tx_id FROM ps_crud ORDER BY id',
      );
      if (mounted) {
        setState(() {
          _rows = rows;
          _crud = crud;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Lesson Debug',
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.primary),
            ),
            right: GestureDetector(
              onTap: _load,
              child: Icon(Icons.refresh, size: 18, color: AppColors.accent),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      Text('dim_lesson: ${_rows.length} row(s) for this user',
                          style: AppFonts.mono(fontSize: 12, color: AppColors.accent)),
                      const SizedBox(height: AppSpacing.sm),
                      if (_error != null)
                        Text('ERROR: $_error',
                            style: AppFonts.mono(fontSize: 11, color: AppColors.danger)),
                      for (final r in _rows) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _row(r),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      Text('ps_crud (upload queue): ${_crud.length} entr(ies)',
                          style: AppFonts.mono(fontSize: 12, color: AppColors.accent)),
                      const SizedBox(height: AppSpacing.sm),
                      if (_crud.isEmpty)
                        Text('(empty — nothing pending upload)',
                            style: AppFonts.ui(fontSize: 12, color: AppColors.muted)),
                      for (final c in _crud)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('id=${c['id']} ${(c['data'] ?? '').toString().substring(0, 120)}',
                              style: AppFonts.mono(fontSize: 10, color: AppColors.muted)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final pinned = r['pinned'] == 1 || r['pinned'] == true;
    final active = r['is_archived'] == 0 || r['is_archived'] == false || r['is_archived'] == null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pinned ? AppColors.accent : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r['exercise_name'] ?? r['custom_exercise_id']}'
              '${pinned ? '  [PINNED]' : ''}${!active ? '  [INACTIVE]' : ''}',
              style: AppFonts.mono(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 2),
          Text('${r['lesson_text']}',
              style: AppFonts.ui(fontSize: 12, color: AppColors.primary)),
          const SizedBox(height: 2),
          Text('id=${r['lesson_id']}  created=${r['lesson_created_date']}',
              style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
        ],
      ),
    );
  }
}
