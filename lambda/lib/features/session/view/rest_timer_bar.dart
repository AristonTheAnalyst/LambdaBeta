import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';

const _holdDuration = Duration(milliseconds: 1500);

/// Bottom bar during an active workout: a Rest-timer chip (left half) and a
/// hold-to-finish button (right half) that ends the workout after a 1.5s
/// press-and-hold, mirroring the Figma reference's "no accidental finish"
/// gesture.
class RestTimerBar extends StatefulWidget {
  const RestTimerBar({super.key, required this.vm, required this.onFinish});

  final SessionViewModel vm;
  final VoidCallback onFinish;

  @override
  State<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends State<RestTimerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _holdCtrl =
      AnimationController(vsync: this, duration: _holdDuration);

  @override
  void initState() {
    super.initState();
    _holdCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinish();
    });
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    super.dispose();
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '${s}s';
  }

  void _openRestModal() {
    showLambdaModal(
      context,
      fitContent: true,
      child: _RestTimerModal(vm: widget.vm),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.vm,
      builder: (context, _) {
        final remaining = widget.vm.restRemaining;
        final active = remaining != null;
        final done = remaining == 0;
        return Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _openRestModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: done ? AppColors.accentBg : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: done ? AppColors.accent : AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        done ? '✓' : active ? _fmt(remaining) : '—',
                        style: AppFonts.mono(
                            fontSize: active ? 16 : 13,
                            fontWeight: FontWeight.w500,
                            color: done ? AppColors.accent : AppColors.primary),
                      ),
                      Text(
                        done ? 'DONE' : 'REST',
                        style: AppFonts.mono(
                            fontSize: 8, letterSpacing: 1, color: done ? AppColors.accent : AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GestureDetector(
                onTapDown: (_) => _holdCtrl.forward(),
                onTapUp: (_) => _holdCtrl.reverse(),
                onTapCancel: () => _holdCtrl.reverse(),
                child: AnimatedBuilder(
                  animation: _holdCtrl,
                  builder: (context, _) => SizedBox(
                    height: 52,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.successBg,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _holdCtrl.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Center(
                            child: Text(
                              _holdCtrl.value > 0 ? 'Hold…' : 'Finish Workout',
                              style: AppFonts.ui(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _holdCtrl.value > 0.5 ? AppColors.accentText : AppColors.success,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RestTimerModal extends StatefulWidget {
  const _RestTimerModal({required this.vm});

  final SessionViewModel vm;

  @override
  State<_RestTimerModal> createState() => _RestTimerModalState();
}

class _RestTimerModalState extends State<_RestTimerModal> {
  final _minCtrl = TextEditingController();
  final _secCtrl = TextEditingController();

  SessionViewModel get vm => widget.vm;

  @override
  void dispose() {
    _minCtrl.dispose();
    _secCtrl.dispose();
    super.dispose();
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _applyCustom() {
    final m = int.tryParse(_minCtrl.text.trim()) ?? 0;
    final s = int.tryParse(_secCtrl.text.trim()) ?? 0;
    final total = m * 60 + s;
    if (total <= 0) return;
    vm.startRest(total);
    _minCtrl.clear();
    _secCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  Widget _durationField(TextEditingController ctrl, String unit) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _applyCustom(),
              style: AppFonts.mono(fontSize: 14, color: AppColors.primary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '0',
                hintStyle: AppFonts.mono(color: AppColors.muted),
              ),
            ),
          ),
          Text(unit, style: AppFonts.mono(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final remaining = vm.restRemaining;
            final active = remaining != null;
            final done = remaining == 0;
            final pct = active && !done ? 1 - (remaining / vm.restTotal) : done ? 1.0 : 0.0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('REST TIMER',
                    style: AppFonts.mono(fontSize: 9, letterSpacing: 1.2, color: AppColors.muted)),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 6,
                          color: AppColors.border,
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: active ? pct : 0,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          color: AppColors.accent,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                      Text(
                        done ? '✓' : active ? _fmt(remaining) : _fmt(vm.restTotal),
                        style: AppFonts.mono(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: done ? AppColors.accent : AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: restPresets
                      .map((p) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: GlassButton(
                                label: p % 60 == 0 ? '${p ~/ 60}m' : '${p ~/ 60}:${(p % 60).toString().padLeft(2, '0')}',
                                compact: true,
                                onPressed: () => vm.startRest(p),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _durationField(_minCtrl, 'm')),
                          const SizedBox(width: 4),
                          Expanded(child: _durationField(_secCtrl, 's')),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    GlassButton(label: 'Set', compact: true, onPressed: _applyCustom),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: !active || done
                            ? 'Start'
                            : vm.restRunning
                                ? 'Pause'
                                : 'Resume',
                        solid: true,
                        onPressed: () {
                          if (!active || done) {
                            vm.startRest(vm.restTotal);
                          } else if (vm.restRunning) {
                            vm.pauseRest();
                          } else {
                            vm.resumeRest();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: GlassButton(
                        label: 'Restart',
                        color: AppColors.muted,
                        onPressed: vm.restartRest,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: GlassButton(
                        label: 'End',
                        color: AppColors.danger,
                        onPressed: () {
                          vm.endRest();
                          Navigator.of(context, rootNavigator: true).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
