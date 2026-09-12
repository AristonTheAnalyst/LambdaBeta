import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../viewmodel/onboarding_viewmodel.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  final _viewModel = OnboardingViewModel();
  int _page = 0;

  static const _slides = [
    _SlideData(
      icon: Icons.timer_outlined,
      title: 'Track Your Workouts',
      body: 'Log sets, track rest periods, and see your progress in real time during every training session.',
    ),
    _SlideData(
      icon: Icons.calendar_month_outlined,
      title: 'Plan with Programs',
      body: 'Create programs with planned workouts, schedule them by day, and let Lambda guide your training.',
    ),
    _SlideData(
      icon: Icons.flag_outlined,
      title: 'Set PRs & Review',
      body: 'Every set is checked against your personal records. Review past sessions, edit history, and see what works.',
    ),
    _SlideData(
      icon: Icons.insights_outlined,
      title: 'Stay Consistent',
      body: 'Built-in rest timer, workout history, exercise library — everything you need to train smarter.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(() {
      final p = _pageCtrl.page?.round() ?? 0;
      if (p != _page) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OnboardingState>(
      valueListenable: _viewModel.state,
      builder: (context, state, _) {
        if (state.success) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            AppRouter.authNotifier.completeOnboarding();
            context.go('/session');
          });
        }

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                if (_page < _slides.length - 1)
                  Align(
                    alignment: Alignment.topRight,
                    child: GlassButton(
                      label: 'Skip',
                      color: AppColors.accent,
                      compact: true,
                      onPressed: _finish,
                    ),
                  ),
                if (state.error != null)
                  Container(
                    width: double.infinity,
                    color: AppColors.dangerBg,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    child: Text(state.error!,
                        style: AppFonts.ui(
                            color: AppColors.danger, fontSize: AppTextStyles.sm)),
                  ),
                Expanded(
                  child: PageView(
                    controller: _pageCtrl,
                    children: _slides.map((s) => _SlideContent(data: s)).toList(),
                  ),
                ),
                // Dots
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      return Container(
                        width: i == _page ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _page ? AppColors.accent : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                  child: LambdaButton(
                    label: _page < _slides.length - 1 ? 'Next' : 'Get Started',
                    onPressed: _page < _slides.length - 1 ? _next : _finish,
                    loading: state.isLoading,
                    disabled: state.isLoading,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _next() => _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  Future<void> _finish() async {
    await _viewModel.submit();
  }
}

class _SlideData {
  const _SlideData({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.data});
  final _SlideData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.accentBg,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(data.icon, size: 48, color: AppColors.accent),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(data.title,
              style: AppFonts.ui(
                  fontSize: AppTextStyles.xl, fontWeight: FontWeight.w800, color: AppColors.primary),
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(data.body,
              style: AppFonts.ui(fontSize: AppTextStyles.md, color: AppColors.muted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
