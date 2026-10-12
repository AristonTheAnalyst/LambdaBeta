import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/page_header.dart';
import '../../reviews/view/reviews_screen.dart';
import 'lab_database.dart';
import 'lab_seed.dart';

/// The review flow lab: the real review screens, running on fake data.
///
/// This page is a door, not a screen. It opens the sandbox database, seeds a
/// small fake world into it the first time, and then hands the screen to the
/// app's own [ReviewsScreen] — so everything from here on is the real flow,
/// unchanged: start a review, pick workouts and goals, walk them, finish it.
/// Nothing reaches Supabase, and nothing shows up in the user's own account.
///
/// Closing the page hands the app's real database back ([LabDatabase.leave]
/// in [dispose]) — the sandbox only ever exists under this screen.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  /// Bumped on reset. The reviews screen is keyed by it so a reset rebuilds it
  /// from scratch — a new view model, reading the new sandbox.
  int _epoch = 0;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await LabDatabase.enter();
      // The page can be popped while the sandbox is still opening (a slow
      // first open, a quick change of mind). dispose() has already run by
      // then, so it will not hand the app database back — this has to.
      if (!mounted) {
        LabDatabase.leave();
        return;
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    await _seed();
  }

  /// Seeds whatever the sandbox is missing and shows the reviews screen. Runs
  /// on boot and after a reset; both paths have to survive a failure the same
  /// way, or the screen is left on a spinner with the reason in the console.
  Future<void> _seed() async {
    try {
      final userId = _userId();
      if (!await labWorldExists(userId)) await seedLabWorld(userId);
      if (mounted) {
        setState(() {
          _epoch++;
          _ready = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The lab keys its rows by user, like everything else, and it sits behind
  /// auth — the dev tab only exists signed in.
  String _userId() {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) throw StateError('The lab needs a signed-in user.');
    return id;
  }

  @override
  void dispose() {
    LabDatabase.leave();
    super.dispose();
  }

  /// Throw the sandbox away and seed it again. Confirmed first: what goes is
  /// only ever fake data, but it may be an hour of the user's own testing.
  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Start the lab over',
            style: AppFonts.ui(
                fontWeight: FontWeight.w800, color: AppColors.primary)),
        content: Text(
            'Throw away everything built in the lab and seed a fresh set of '
            'fake workouts, goals and reviews? Your own data is untouched.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child:
                  Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Start over',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _ready = false;
      _error = null;
    });
    await LabDatabase.reset();
    await _seed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Review Flow',
            left: GestureDetector(
              // Back out of the lab, and never fail to. For as long as this
              // page is open the app's database pointer is the SANDBOX, so a
              // back button that cannot leave would strand every other screen
              // on fake data. The dev card pushes the lab (leaving /dev
              // beneath it), but a `go` straight to /dev/lab leaves it as the
              // only page — and a bare pop there trips go_router's
              // "no pages left" assert and wedges the navigator.
              onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/dev');
                }
              },
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: AppColors.accent),
            ),
            right: _ready
                ? GestureDetector(
                    onTap: _reset,
                    child: Icon(Icons.restart_alt,
                        size: 20, color: AppColors.accent),
                  )
                : null,
          ),
          const _SandboxBanner(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'The lab could not open its sandbox.\n$error',
            textAlign: TextAlign.center,
            style: AppFonts.ui(
                fontSize: AppTextStyles.sm, color: AppColors.danger),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // The real reviews screen, headerless — this page owns the header, and so
    // does the Library tab it is otherwise embedded in.
    return ReviewsScreen(key: ValueKey(_epoch), showHeader: false);
  }
}

/// Says what this is, on the lab's own screen. Deeper in, the screens are
/// the real ones and carry no banner — there, the seeded ("Push Day", "Base
/// Block") naming is what keeps the sandbox from being mistaken for the
/// account.
class _SandboxBanner extends StatelessWidget {
  const _SandboxBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: AppColors.plannedBg,
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 14, color: AppColors.planned),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Sandbox · fake data. Nothing built here reaches your account.',
              style: AppFonts.ui(
                  fontSize: AppTextStyles.xs, color: AppColors.planned),
            ),
          ),
        ],
      ),
    );
  }
}
