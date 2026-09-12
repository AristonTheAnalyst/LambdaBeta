import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../viewmodel/auth_viewmodel.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController           = TextEditingController();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _viewModel                 = AuthViewModel();
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_clearEmailError);
    _passwordController.addListener(_clearPasswordError);
    _confirmPasswordController.addListener(_clearConfirmPasswordError);
  }

  void _clearEmailError() {
    if (_emailError != null) setState(() => _emailError = null);
  }

  void _clearPasswordError() {
    if (_passwordError != null) setState(() => _passwordError = null);
  }

  void _clearConfirmPasswordError() {
    if (_confirmPasswordError != null) {
      setState(() => _confirmPasswordError = null);
    }
  }

  bool _validate() {
    final emailErr   = Validators.email(_emailController.text.trim());
    final passErr    = Validators.password(_passwordController.text);
    final confirmErr = Validators.confirmPassword(
      _passwordController.text,
      _confirmPasswordController.text,
    );
    setState(() {
      _emailError           = emailErr;
      _passwordError        = passErr;
      _confirmPasswordError = confirmErr;
    });
    return emailErr == null && passErr == null && confirmErr == null;
  }

  Future<void> _handleSignup() async {
    if (!_validate()) return;
    await _viewModel.signUp(
      _emailController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearEmailError);
    _passwordController.removeListener(_clearPasswordError);
    _confirmPasswordController.removeListener(_clearConfirmPasswordError);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
            return Column(
              children: [
                // Back button — pinned to top
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left,
                            color: AppColors.accent,
                            size: 20,
                          ),
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
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height -
                            MediaQuery.of(context).padding.top -
                            MediaQuery.of(context).padding.bottom -
                            56,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Error banner
                            if (state.error != null) ...[
                              GestureDetector(
                                onTap: _viewModel.clearError,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerBg,
                                    border: Border.all(
                                        color: AppColors.dangerBorder),
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

                            // Header
                            Column(
                              children: [
                                Text(
                                  'Lambda',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: AppTextStyles.lg,
                                    color: AppColors.muted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            SizedBox(height: 32),

                            LambdaInput(
                              controller: _emailController,
                              label: 'Email',
                              placeholder: 'Enter your email',
                              error: _emailError,
                              enabled: !state.isBusy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                            ),
                            SizedBox(height: 16),

                            LambdaInput(
                              controller: _passwordController,
                              label: 'Password',
                              placeholder: 'Enter password (min 6 characters)',
                              error: _passwordError,
                              enabled: !state.isBusy,
                              obscureText: true,
                              textInputAction: TextInputAction.next,
                            ),
                            SizedBox(height: 16),

                            LambdaInput(
                              controller: _confirmPasswordController,
                              label: 'Confirm Password',
                              placeholder: 'Confirm your password',
                              error: _confirmPasswordError,
                              enabled: !state.isBusy,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!state.isBusy) _handleSignup();
                              },
                            ),
                            SizedBox(height: 24),

                            LambdaButton(
                              label: 'Sign Up',
                              onPressed: _handleSignup,
                              loading: state.isLoading,
                              disabled: state.isBusy,
                            ),
                            SizedBox(height: 24),

                            // OR divider
                            Row(
                              children: [
                                Expanded(child: Divider(color: AppColors.border)),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'or',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppTextStyles.sm,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: AppColors.border)),
                              ],
                            ),
                            SizedBox(height: 24),

                            // Social buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _SocialButton(
                                  icon: FontAwesomeIcons.google,
                                  loading: state.socialLoading ==
                                      SocialProvider.google,
                                  disabled: state.isBusy,
                                  onTap: _viewModel.signInWithGoogle,
                                ),
                                if (Platform.isIOS) ...[
                                  SizedBox(width: 24),
                                  _SocialButton(
                                    icon: FontAwesomeIcons.apple,
                                    iconSize: 26,
                                    loading: state.socialLoading ==
                                        SocialProvider.apple,
                                    disabled: state.isBusy,
                                    onTap: _viewModel.signInWithApple,
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 24,
    this.loading = false,
    this.disabled = false,
  });

  final FaIconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: loading ? 0.5 : 1.0,
        child: Container(
          width: 56,
          height: 56,
          // The glass recipe — the same pressable chrome as every button.
          decoration: glassBox(AppColors.primary, radius: 8),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : FaIcon(icon, size: iconSize, color: AppColors.primary),
        ),
      ),
    );
  }
}
