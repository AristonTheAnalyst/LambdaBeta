import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../viewmodel/auth_viewmodel.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _viewModel       = AuthViewModel();
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() {
      if (_emailError != null) setState(() => _emailError = null);
    });
  }

  Future<void> _handleSend() async {
    final error = Validators.email(_emailController.text.trim());
    if (error != null) {
      setState(() => _emailError = error);
      return;
    }
    await _viewModel.resetPassword(_emailController.text.trim());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ValueListenableBuilder<AuthFormState>(
          valueListenable: _viewModel.state,
          builder: (context, state, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 16),

                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chevron_left,
                              color: AppColors.accent, size: 20),
                          Text(
                            'Back',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: AppTextStyles.sm,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Text(
                          'Reset Password',
                          style: TextStyle(
                            fontSize: AppTextStyles.xxl,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          state.emailSent
                              ? 'Check your email for a reset link.'
                              : "Enter your email and we'll send you a reset link.",
                          style: TextStyle(
                            fontSize: AppTextStyles.md,
                            color: AppColors.muted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 32),

                        // Error banner
                        if (state.error != null) ...[
                          GestureDetector(
                            onTap: _viewModel.clearError,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.dangerBg,
                                border:
                                    Border.all(color: AppColors.dangerBorder),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                state.error!,
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: AppTextStyles.sm,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                        ],

                        if (!state.emailSent) ...[
                          LambdaInput(
                            controller: _emailController,
                            label: 'Email',
                            placeholder: 'Enter your email',
                            error: _emailError,
                            enabled: !state.isBusy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!state.isBusy) _handleSend();
                            },
                          ),
                          SizedBox(height: 24),
                          LambdaButton(
                            label: 'Send Reset Link',
                            onPressed: _handleSend,
                            loading: state.isLoading,
                            disabled: state.isBusy,
                          ),
                          SizedBox(height: 16),
                        ],

                        LambdaButton(
                          label: 'Back to Login',
                          onPressed: () => context.pop(),
                          variant: ButtonVariant.ghost,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
