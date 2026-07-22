import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../viewmodel/reset_password_viewmodel.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _viewModel                 = ResetPasswordViewModel();
  String? _passwordError;
  String? _confirmError;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_clearPasswordError);
    _confirmPasswordController.addListener(_clearConfirmError);
  }

  void _clearPasswordError() {
    if (_passwordError != null) setState(() => _passwordError = null);
  }

  void _clearConfirmError() {
    if (_confirmError != null) setState(() => _confirmError = null);
  }

  bool _validate() {
    final passErr    = Validators.password(_passwordController.text);
    final confirmErr = Validators.confirmPassword(
        _passwordController.text, _confirmPasswordController.text);
    setState(() {
      _passwordError = passErr;
      _confirmError  = confirmErr;
    });
    return passErr == null && confirmErr == null;
  }

  Future<void> _handleSubmit() async {
    if (!_validate()) return;
    await _viewModel.updatePassword(_passwordController.text);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_clearPasswordError);
    _confirmPasswordController.removeListener(_clearConfirmError);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // block back during recovery flow
      child: Scaffold(
        backgroundColor: AppColors.bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: ValueListenableBuilder<ResetPasswordState>(
            valueListenable: _viewModel.state,
            builder: (context, state, _) {
              if (state.success) {
                return _SuccessView(onContinue: () => context.go('/session'));
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.error != null) ...[
                          GestureDetector(
                            onTap: _viewModel.clearError,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.dangerBg,
                                border: Border.all(color: AppColors.dangerBorder),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                state.error!,
                                style: TextStyle(
                                    color: AppColors.danger,
                                    fontSize: AppTextStyles.sm),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                        ],

                        Column(
                          children: [
                            Text(
                              'New Password',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Choose a new password for your account',
                              style: TextStyle(
                                  fontSize: AppTextStyles.md,
                                  color: AppColors.muted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        SizedBox(height: 32),

                        LambdaInput(
                          controller: _passwordController,
                          label: 'New password',
                          placeholder: 'At least 6 characters',
                          error: _passwordError,
                          enabled: !state.isLoading,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: 16),

                        LambdaInput(
                          controller: _confirmPasswordController,
                          label: 'Confirm password',
                          placeholder: 'Repeat your password',
                          error: _confirmError,
                          enabled: !state.isLoading,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!state.isLoading) _handleSubmit();
                          },
                        ),
                        SizedBox(height: 24),

                        LambdaButton(
                          label: 'Update Password',
                          onPressed: _handleSubmit,
                          loading: state.isLoading,
                          disabled: state.isLoading,
                        ),
                        SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: AppColors.accent),
          SizedBox(height: 24),
          Text(
            'Password updated!',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Your password has been changed successfully.',
            style: TextStyle(fontSize: AppTextStyles.md, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
          LambdaButton(
            label: 'Continue',
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
