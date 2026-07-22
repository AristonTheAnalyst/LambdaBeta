import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../viewmodel/onboarding_viewmodel.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _heightController    = TextEditingController();
  final _weightController    = TextEditingController();
  final _viewModel           = OnboardingViewModel();

  static const _genderOptions = [
    DropdownOption(label: 'Male',   value: 'male'),
    DropdownOption(label: 'Female', value: 'female'),
    DropdownOption(label: 'Other',  value: 'other'),
  ];

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(
        () => _viewModel.setFirstName(_firstNameController.text));
    _lastNameController.addListener(
        () => _viewModel.setLastName(_lastNameController.text));
  }

  Future<void> _pickDate(OnboardingState state) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: state.dateOfBirth ??
          DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: AppColors.accentText,
            surface: AppColors.surface,
            onSurface: AppColors.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) _viewModel.setDateOfBirth(picked);
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ValueListenableBuilder<OnboardingState>(
          valueListenable: _viewModel.state,
          builder: (context, state, _) {
            // Navigate as soon as submit succeeds
            if (state.success) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                AppRouter.authNotifier.completeOnboarding();
                context.go('/session');
              });
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Header
                  Text(
                    'Tell us about yourself',
                    style: TextStyle(
                      fontSize: AppTextStyles.xxl,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'ll use this to personalise your experience',
                    style: TextStyle(
                        fontSize: AppTextStyles.md, color: AppColors.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Error banner
                  if (state.error != null) ...[
                    Container(
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
                    const SizedBox(height: 16),
                  ],

                  // First name
                  LambdaInput(
                    controller: _firstNameController,
                    label: 'First name',
                    placeholder: 'Enter your first name',
                    enabled: !state.isLoading,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Last name
                  LambdaInput(
                    controller: _lastNameController,
                    label: 'Last name',
                    placeholder: 'Enter your last name',
                    enabled: !state.isLoading,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Date of birth
                  _FieldLabel('Date of birth (optional)'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: state.isLoading ? null : () => _pickDate(state),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              state.dateOfBirth != null
                                  ? _formatDate(state.dateOfBirth!)
                                  : 'Select date',
                              style: TextStyle(
                                fontSize: AppTextStyles.md,
                                color: state.dateOfBirth != null
                                    ? AppColors.primary
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                          Icon(Icons.calendar_today_outlined,
                              size: 18, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gender
                  _FieldLabel('Gender (optional)'),
                  const SizedBox(height: 6),
                  DropdownSelect<String>(
                    options: _genderOptions,
                    value: state.gender,
                    onChange: _viewModel.setGender,
                    placeholder: 'Select gender',
                  ),
                  const SizedBox(height: 16),

                  // Height
                  LambdaInput(
                    controller: _heightController,
                    label: 'Height in cm (optional)',
                    placeholder: 'e.g. 175',
                    enabled: !state.isLoading,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textInputAction: TextInputAction.next,
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      _viewModel.setHeightCm(parsed);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Weight
                  LambdaInput(
                    controller: _weightController,
                    label: 'Weight in kg (optional)',
                    placeholder: 'e.g. 75',
                    enabled: !state.isLoading,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textInputAction: TextInputAction.done,
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      _viewModel.setWeightKg(parsed);
                    },
                  ),
                  const SizedBox(height: 32),

                  LambdaButton(
                    label: 'Get Started',
                    onPressed: _viewModel.submit,
                    loading: state.isLoading,
                    disabled: state.isLoading,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }
}
