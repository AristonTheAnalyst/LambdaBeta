import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../data/models/name_change.dart';
import '../../data/repositories/name_change_repository.dart';
import 'glass_button.dart';
import 'header_icon_button.dart';
import 'slide_up_modal.dart';
import 'user_name_text.dart';

/// The owner's rename history for one exercise, variation or workout
/// (2026-10-29).
///
/// Every rename is logged server-side with who made it and when, so a name
/// that changed under the user — by them, or by a coach acting on their
/// behalf — can be seen and put back. Restoring is another rename through the
/// same write path, so it records itself and the list refreshes in place.
///
/// Owner-only by construction: the row stream sends a history to
/// `user_id = auth.user_id()`, so a coach's device holds none of the owner's
/// history and the surfaces that open this sheet only offer it on the
/// owner's own mount.
Future<void> showNameHistorySheet(
  BuildContext context, {
  required String userId,
  required String entityType,
  required String entityId,
  required String currentName,
  required Future<void> Function(String name) onRestore,
}) {
  return showLambdaModal(
    context,
    fitContent: true,
    backgroundColor: AppColors.bg,
    child: _NameHistorySheet(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      currentName: currentName,
      onRestore: onRestore,
    ),
  );
}

class _NameHistorySheet extends StatefulWidget {
  const _NameHistorySheet({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.currentName,
    required this.onRestore,
  });

  final String userId;
  final String entityType;
  final String entityId;
  final String currentName;
  final Future<void> Function(String name) onRestore;

  @override
  State<_NameHistorySheet> createState() => _NameHistorySheetState();
}

class _NameHistorySheetState extends State<_NameHistorySheet> {
  final _repo = NameChangeRepository();
  List<NameChange>? _rows;
  String? _error;
  late String _current = widget.currentName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _repo.fetchNameChanges(
        userId: widget.userId,
        entityType: widget.entityType,
        entityId: widget.entityId,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _restore(NameChange change) async {
    final name = change.oldName;
    if (name == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRestore(name);
      if (!mounted) return;
      setState(() => _current = name);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = switch (widget.entityType) {
      'variation' => 'variation',
      'workout' => 'workout',
      _ => 'exercise',
    };
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
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
                      'Name History',
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  HeaderIconButton(
                    icon: Icons.close,
                    semanticsLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                'Every rename of this $noun, who made it and when.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  height: 1.4,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null)
                Text(
                  _error!,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.danger,
                  ),
                )
              else if (_rows == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xl,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                    ),
                  ),
                )
              else if (_rows!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xl,
                  ),
                  child: Text(
                    'No name changes yet.',
                    textAlign: TextAlign.center,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _rows!.length,
                    separatorBuilder: (_, _) => const SizedBox(
                      height: AppSpacing.sm,
                    ),
                    itemBuilder: (context, i) => _row(_rows![i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(NameChange change) {
    final canRestore =
        change.oldName != null && change.oldName != _current && !_busy;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserNameText(
                  '${change.oldName ?? ''} → ${change.newName ?? ''}',
                  tooltip: true,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${change.byCoach ? 'Your coach' : 'You'} · '
                  '${DateFormat('d MMM yyyy · HH:mm').format(change.changedAt)}',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (canRestore) ...[
            const SizedBox(width: AppSpacing.sm),
            GlassButton(
              label: 'Restore',
              compact: true,
              onPressed: () => _restore(change),
            ),
          ],
        ],
      ),
    );
  }
}
