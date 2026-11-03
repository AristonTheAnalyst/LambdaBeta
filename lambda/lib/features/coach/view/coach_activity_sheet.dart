import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/coach_activity.dart';
import '../../../data/repositories/coach_activity_repository.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';

/// “From your coach” (2026-10-29): what the coach has added, edited or
/// renamed in the viewer's training, derived from the audit columns and the
/// name history. The in-app side of the “nothing is silent” rule; push comes
/// later.
Future<void> showCoachActivitySheet(BuildContext context) {
  return showLambdaModal(
    context,
    fitContent: true,
    backgroundColor: AppColors.bg,
    child: const _CoachActivitySheet(),
  );
}

class _CoachActivitySheet extends StatefulWidget {
  const _CoachActivitySheet();

  @override
  State<_CoachActivitySheet> createState() => _CoachActivitySheetState();
}

class _CoachActivitySheetState extends State<_CoachActivitySheet> {
  final _repo = CoachActivityRepository();
  List<CoachActivityEntry>? _entries;
  String? _coachName;
  String? _error;
  bool _noCoach = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final coachId = await _repo.coachIdFor(userId);
      if (coachId == null) {
        if (mounted) setState(() => _noCoach = true);
        return;
      }
      final name = await _repo.coachNameFor(coachId);
      final entries = await _repo.fetch(userId: userId, coachId: coachId);
      if (!mounted) return;
      setState(() {
        _coachName = name;
        _entries = entries;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'From your coach',
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  HeaderIconButton(
                    icon: LucideIcons.x,
                    semanticsLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                _coachName?.trim().isNotEmpty == true
                    ? 'Changes ${_coachName!.trim()} made to your training.'
                    : 'Changes your coach made to your training.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  height: 1.4,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          _error!,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.danger,
          ),
        ),
      );
    }
    if (_noCoach) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          'You have no coach yet.',
          textAlign: TextAlign.center,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.inkSecondary,
          ),
        ),
      );
    }
    final entries = _entries;
    if (entries == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          'Nothing from your coach yet.',
          textAlign: TextAlign.center,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.inkSecondary,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) => _row(entries[i]),
    );
  }

  Widget _row(CoachActivityEntry e) {
    final (icon, color, verb) = switch (e.kind) {
      CoachActivityKind.added => (
        LucideIcons.circlePlus,
        AppColors.success,
        'Added',
      ),
      CoachActivityKind.edited => (
        LucideIcons.pencil,
        AppColors.primary,
        'Edited',
      ),
      CoachActivityKind.renamed => (
        LucideIcons.history,
        AppColors.primary,
        'Renamed',
      ),
    };
    final article = e.label.startsWith(RegExp('[aeiou]')) ? 'an' : 'a';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$verb $article ${e.label}',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                UserNameText(
                  e.name,
                  tooltip: true,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  DateFormat('d MMM yyyy · HH:mm').format(e.at),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
