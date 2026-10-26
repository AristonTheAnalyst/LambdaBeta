import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/athlete.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../viewmodel/coach_viewmodel.dart';

/// The Coach roster (2026-10-26), reached from Profile.
///
/// It lists the athletes who have accepted a coaching relationship — nobody
/// else exists here, because the stream only sends accepted relationships'
/// athlete data. Tapping one opens their completed history in the same
/// read-only viewer the Friends list uses: the Training Logs list pointed at
/// their id, and from a card the past-session viewer with every write
/// affordance gone.
///
/// #22 grows this page its pending invitations, invite-by-code sheet and
/// revoke — the rows here already carry [Athlete.acceptedDate] for that split.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, this.viewModel});

  /// A caller-supplied roster (host tests); null builds its own.
  final CoachViewModel? viewModel;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  late final CoachViewModel _vm = widget.viewModel ?? CoachViewModel();

  /// Whether [_vm] is this screen's to dispose. An injected view model belongs
  /// to whoever passed it — a host test goes on asserting against it after the
  /// widget is gone.
  late final bool _ownsVm = widget.viewModel == null;

  @override
  void initState() {
    super.initState();
    _vm.start();
  }

  @override
  void dispose() {
    if (_ownsVm) _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<CoachState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          return Column(
            children: [
              PageHeader(
                title: 'Coach',
                left: HeaderIconButton(
                  icon: Icons.arrow_back_ios_new,
                  semanticsLabel: 'Back',
                  glyphSize: 18,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/profile'),
                ),
              ),
              Expanded(
                child: ListView(
                  // The shell's bar floats over this page, so the last row
                  // has to scroll clear of it.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
                  ),
                  children: [
                    _SectionCaption(count: state.athletes.length),
                    const SizedBox(height: AppSpacing.sm),
                    if (state.isLoading && state.athletes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxl),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    else if (state.athletes.isEmpty)
                      const _EmptyAthletes()
                    else
                      for (var i = 0; i < state.athletes.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.md),
                        _AthleteRow(
                          athlete: state.athletes[i],
                          onTap: () => context.push(
                            '/profile/coach/${state.athletes[i].userId}',
                            extra: state.athletes[i].displayName,
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'ATHLETES',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkSecondary,
          ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

class _AthleteRow extends StatelessWidget {
  const _AthleteRow({required this.athlete, required this.onTap});

  final Athlete athlete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: ValueKey(athlete.userId),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: UserNameText(
              athlete.displayName,
              style: AppFonts.ui(
                fontSize: AppTextStyles.body,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _EmptyAthletes extends StatelessWidget {
  const _EmptyAthletes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(Icons.sports_outlined, size: 28, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No athletes yet',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'An athlete appears here after accepting your coaching '
              'invitation.',
              textAlign: TextAlign.center,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
