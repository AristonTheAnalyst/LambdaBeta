import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/session.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../logs/view/session_detail_screen.dart';
import '../../logs/viewmodel/session_detail_viewmodel.dart';
import '../viewmodel/session_viewmodel.dart';

/// The another-device session, READ before deciding (2026-10-15) — what the
/// notice's Preview opens. This is the shared past-session viewer in its
/// read-only mode: the same exercises, sets, PRs and history, nothing
/// editable and nothing written. The bar under it holds the one write —
/// **Switch to this session**, which trades this device's own session for it
/// (asking cancel-or-complete first when there is one), and closes back to
/// the session screen once the switch lands.
///
/// A session that ends on the other device while it is being read answers
/// Switch with "it has ended" on the bar instead of switching — the row it
/// would adopt is no longer live.
///
/// The screen is a storey stack (2026-10-27): the viewer's own floor — date
/// selector, then the action row — then this screen's Switch band, then the
/// shell's floating nav bar. The band is what clears the bar
/// ([ScrollShrinkNavBar.contentInset]); the floor above it spends only its
/// own row's air, so the three stack at the floor's rhythm instead of the
/// Switch button landing under the bar.
class ForeignSessionPreviewScreen extends StatefulWidget {
  const ForeignSessionPreviewScreen({
    super.key,
    required this.session,
    required this.vm,
  });

  /// The other device's live session, as the notice read it.
  final Session session;

  /// The live session VM that owns the switch (and this device's own
  /// session, if any).
  final SessionViewModel vm;

  @override
  State<ForeignSessionPreviewScreen> createState() =>
      _ForeignSessionPreviewScreenState();
}

class _ForeignSessionPreviewScreenState
    extends State<ForeignSessionPreviewScreen> {
  late final SessionDetailViewModel _detail = SessionDetailViewModel(
    userId: widget.session.userId,
  );
  bool _switching = false;
  String? _endedNotice;

  @override
  void initState() {
    super.initState();
    _detail.load(widget.session.sessionId);
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _switch() async {
    if (_switching) return;
    final vm = widget.vm;
    var completeMine = false;
    if (vm.hasActiveWorkout) {
      // The follow-up: the user chose Switch, and this device has its own
      // session — cancel it or complete it first (dismissing backs out;
      // nothing switches).
      final complete = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Switch Sessions',
            style: AppFonts.ui(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          content: Text(
            'Switching trades this device\'s session for the one started '
            'elsewhere.\n\n'
            'Cancel mine discards it and its logged sets. Complete mine ends '
            'it and files it in the logs.',
            style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel mine',
                style: AppFonts.ui(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Complete mine',
                style: AppFonts.ui(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      if (complete == null || !mounted) return;
      completeMine = complete;
    }
    setState(() {
      _switching = true;
      _endedNotice = null;
    });
    final switched = await vm.switchToForeignSession(
      widget.session.sessionId,
      completeMine: completeMine,
    );
    if (!mounted) return;
    if (switched) {
      // The session screen is the live one now — this reading is done.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _switching = false;
      _endedNotice =
          'That session has ended on its device — nothing to '
          'switch to.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final started = DateFormat.jm().format(
      widget.session.createdDatetime.toLocal(),
    );
    final title = widget.session.plannedSessionName ?? 'Open Session';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<SessionDetailState>(
        valueListenable: _detail.state,
        builder: (context, state, _) => Column(
          children: [
            PageHeader(
              title: title,
              left: HeaderIconButton(
                icon: LucideIcons.chevronLeft,
                semanticsLabel: 'Back',
                glyphSize: 18,
                color: AppColors.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (state.isLoading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else
              // The shared viewer, view mode — looking is not writing. The
              // floor keeps only its own row's air (2026-10-27): the Switch
              // band below stands between it and the nav bar, and the band is
              // what clears the bar — the floor reserving it too would seat
              // the band under it.
              Expanded(
                child: SessionDetailView(
                  viewModel: _detail,
                  state: state,
                  floorBottomInset: AppSpacing.sm,
                ),
              ),
            Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                // Clear the shell's floating bar (2026-10-27) — the band is
                // the last thing above it now, so the inset that used to sit
                // under the viewer's floor sits here instead. Its 16 of air
                // is the gap that reads between the band and the bar.
                ScrollShrinkNavBar.contentInset(context),
              ),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _endedNotice ??
                        'In progress on another device — started $started.',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.xs,
                      color: _endedNotice != null
                          ? AppColors.danger
                          : AppColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GlassButton(
                    label: 'Switch to this session',
                    loading: _switching,
                    disabled: _switching,
                    onPressed: _switch,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
