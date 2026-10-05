import 'package:flutter/material.dart';
import '../../../shared/widgets/container_styles.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/block_length.dart';
import '../../../../shared/widgets/dob_picker.dart';
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../../shared/widgets/lambda_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../viewmodel/profile_viewmodel.dart';

class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({super.key});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> with UnsavedChangesGuard<ProfileDetailScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _heightController    = TextEditingController();
  final _weightController    = TextEditingController();
  final _viewModel           = ProfileViewModel();

  DateTime? _editDob;
  String? _editGender;

  // ── UnsavedChangesGuard overrides ─────────────────────────────────────────

  /// Whether the form holds something different from what is stored.
  ///
  /// "In edit mode" is not the same as "changed": entering edit mode and
  /// pressing Save wrote the loaded values straight back. The guard asks this
  /// question on the way out, and the Save button draws its visibility from it,
  /// so one comparison answers both.
  @override
  bool get hasUnsavedChanges {
    if (!_viewModel.state.value.isEditing) return false;
    final p = _viewModel.state.value.profile;
    return _firstNameController.text.trim() != (p?.userName ?? '').trim() ||
        _lastNameController.text.trim() != (p?.userLastname ?? '').trim() ||
        // Parsed, not compared as text: "180" and "180.0" are one weight.
        double.tryParse(_heightController.text) != p?.userHeightCm ||
        double.tryParse(_weightController.text) != p?.userWeightKg ||
        !sameCalendarDay(_editDob, p?.userDateOfBirth) ||
        // '' and null are one answer — "not specified".
        (_editGender ?? '') != (p?.userGender ?? '');
  }

  @override
  Future<void> onSave() async => await _handleSave();

  @override
  void onDiscard() => _viewModel.cancelEditing();

  static const _genderOptions = [
    DropdownOption(label: 'Not specified', value: ''),
    DropdownOption(label: 'Male',          value: 'Male'),
    DropdownOption(label: 'Female',        value: 'Female'),
    DropdownOption(label: 'Other',         value: 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _viewModel.loadProfile();
    // Save's visibility is a comparison against the stored profile, so the
    // form has to rebuild as it is typed into.
    for (final c in _formControllers) {
      c.addListener(_onFormChanged);
    }
  }

  List<TextEditingController> get _formControllers => [
        _firstNameController,
        _lastNameController,
        _heightController,
        _weightController,
      ];

  void _onFormChanged() => setState(() {});

  void _populateEditFields() {
    final p = _viewModel.state.value.profile;
    _firstNameController.text = p?.userName ?? '';
    _lastNameController.text  = p?.userLastname ?? '';
    _heightController.text    = p?.userHeightCm?.toString() ?? '';
    _weightController.text    = p?.userWeightKg?.toString() ?? '';
    _editDob    = p?.userDateOfBirth;
    _editGender = p?.userGender;
  }

  Future<void> _pickDate() async {
    // The custom calendar sheet — same language as the logs date filter,
    // instead of the stock Material date picker.
    final picked = await showDateOfBirthPicker(context, initial: _editDob);
    if (picked != null) setState(() => _editDob = picked);
  }

  Future<void> _handleSave() async {
    await _viewModel.saveProfile(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      dateOfBirth: _editDob,
      gender: _editGender,
      heightCm: double.tryParse(_heightController.text),
      weightKg: double.tryParse(_weightController.text),
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout',
            style: TextStyle(color: AppColors.primary)),
        content: Text('Are you sure you want to logout?',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _viewModel.signOut();
            },
            child: Text('Logout',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Account',
            style: TextStyle(color: AppColors.danger)),
        content: Text(
          'This will permanently delete your account and all associated data. This cannot be undone.',
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _viewModel.deleteAccount();
            },
            child: Text('Delete',
                style: TextStyle(color: AppColors.danger,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  @override
  void dispose() {
    // The controllers carry the rebuild listeners while the form is alive;
    // disposing them releases both.
    _firstNameController.dispose();
    _lastNameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildGuardedScaffold(
      scaffold: Scaffold(
        backgroundColor: AppColors.bg,
        resizeToAvoidBottomInset: true,
        body: ValueListenableBuilder<ProfileState>(
          valueListenable: _viewModel.state,
          builder: (context, state, _) {
            return Column(
              children: [
                PageHeader(
                  title: 'User Profile',
                  left: GestureDetector(
                    onTap: () async {
                      final nav = Navigator.of(context);
                      if (await confirmBack() && mounted) {
                        nav.pop();
                      }
                    },
                    child: Icon(Icons.arrow_back_ios_new,
                        size: 18, color: AppColors.accent),
                  ),
                  right: !state.isEditing
                      ? GlassButton(
                          label: 'Edit',
                          onPressed: () {
                            _populateEditFields();
                            _viewModel.startEditing();
                          },
                          compact: true,
                        )
                      : null,
                ),
                if (state.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      border: Border.all(color: AppColors.dangerBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(state.error!,
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: AppTextStyles.sm),
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (state.saveSuccess)
                  Container(
                    width: double.infinity,
                    color: AppColors.successBg,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    child: Text('Profile saved.',
                        style: AppFonts.ui(
                            color: AppColors.success, fontSize: AppTextStyles.sm)),
                  ),
                Expanded(
                child: KeyboardDismissOnScroll(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Email (always read-only)
                        _ProfileRow(
                          label: 'Email',
                          child: Text(
                            _emailDisplay(),
                            style: TextStyle(
                                fontSize: AppTextStyles.md,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary),
                          ),
                        ),

                        // Name
                        _ProfileRow(
                          label: 'Name',
                          child: state.isEditing
                              ? Row(children: [
                                  Expanded(
                                    child: LambdaInput(
                                      controller: _firstNameController,
                                      placeholder: 'First',
                                      enabled: !state.isBusy,
                                      textInputAction: TextInputAction.next,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: LambdaInput(
                                      controller: _lastNameController,
                                      placeholder: 'Last',
                                      enabled: !state.isBusy,
                                      textInputAction: TextInputAction.next,
                                    ),
                                  ),
                                ])
                              : Text(
                                  [state.profile?.userName,
                                   state.profile?.userLastname]
                                      .where((s) => s?.isNotEmpty == true)
                                      .join(' ')
                                      .isNotEmpty
                                      ? [state.profile?.userName,
                                         state.profile?.userLastname]
                                            .where((s) =>
                                                s?.isNotEmpty == true)
                                            .join(' ')
                                      : '—',
                                  style: TextStyle(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary),
                                ),
                        ),

                        // Date of Birth
                        _ProfileRow(
                          label: 'Date of Birth',
                          child: state.isEditing
                              ? GestureDetector(
                                  onTap: state.isBusy ? null : _pickDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    decoration: glassBox(AppColors.primary, radius: 8),
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(
                                          _editDob != null
                                              ? _formatDate(_editDob!)
                                              : 'Select date',
                                          style: TextStyle(
                                              fontSize: AppTextStyles.md,
                                              color: _editDob != null
                                                  ? AppColors.primary
                                                  : AppColors.muted),
                                        ),
                                      ),
                                      Icon(Icons.calendar_today_outlined,
                                          size: 18, color: AppColors.muted),
                                    ]),
                                  ),
                                )
                              : Text(
                                  state.profile?.userDateOfBirth != null
                                      ? _formatDate(
                                          state.profile!.userDateOfBirth!)
                                      : '—',
                                  style: TextStyle(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary),
                                ),
                        ),

                        // Gender
                        _ProfileRow(
                          label: 'Gender',
                          child: state.isEditing
                              ? DropdownSelect<String>(
                                  options: _genderOptions,
                                  value: _editGender ?? '',
                                  onChange: (v) =>
                                      setState(() => _editGender = v),
                                  placeholder: 'Not specified',
                                )
                              : Text(
                                  state.profile?.userGender?.isNotEmpty ==
                                          true
                                      ? state.profile!.userGender!
                                      : '—',
                                  style: TextStyle(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary),
                                ),
                        ),

                        // Height
                        _ProfileRow(
                          label: 'Height (cm)',
                          child: state.isEditing
                              ? LambdaInput(
                                  controller: _heightController,
                                  placeholder: 'e.g. 175',
                                  enabled: !state.isBusy,
                                  keyboardType:
                                      TextInputType.numberWithOptions(
                                          decimal: false),
                                  textInputAction: TextInputAction.next,
                                )
                              : Text(
                                  state.profile?.userHeightCm != null
                                      ? '${state.profile!.userHeightCm!.toInt()} cm'
                                      : '—',
                                  style: TextStyle(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary),
                                ),
                        ),

                        // Weight
                        _ProfileRow(
                          label: 'Weight (kg)',
                          isLast: true,
                          child: state.isEditing
                              ? LambdaInput(
                                  controller: _weightController,
                                  placeholder: 'e.g. 75',
                                  enabled: !state.isBusy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textInputAction: TextInputAction.done,
                                )
                              : Text(
                                  state.profile?.userWeightKg != null
                                      ? '${state.profile!.userWeightKg} kg'
                                      : '—',
                                  style: TextStyle(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary),
                                ),
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        // Actions
                        if (state.isEditing) ...[
                          Row(
                            children: [
                              Expanded(
                                child: LambdaButton(
                                  label: 'Cancel',
                                  variant: ButtonVariant.ghost,
                                  onPressed: _viewModel.cancelEditing,
                                  disabled: state.isBusy,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              // Only once there is something to save —
                              // Cancel alone is the row's honest state on an
                              // untouched form.
                              if (hasUnsavedChanges)
                                Expanded(
                                  child: LambdaButton(
                                    label: 'Save',
                                    onPressed: _handleSave,
                                    loading: state.isSaving,
                                    disabled: state.isBusy,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          LambdaButton(
                            label: 'Delete Account',
                            variant: ButtonVariant.danger,
                            onPressed: _confirmDelete,
                            loading: state.isDeleting,
                            disabled: state.isBusy,
                          ),
                        ] else ...[
                          const SizedBox(height: AppSpacing.xxl),
                          LambdaButton(
                            label: 'Logout',
                            onPressed: _confirmLogout,
                          ),
                        ],

                        const SizedBox(height: AppSpacing.xxl),
                      ],
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

  String _emailDisplay() {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    if (email.endsWith('@privaterelay.appleid.com')) {
      return 'Signed in with Apple';
    }
    return email.isNotEmpty ? email : '—';
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.child,
    this.isLast = false,
  });

  final String label;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: AppTextStyles.xs, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

// Dismiss keyboard when user scrolls
class KeyboardDismissOnScroll extends StatelessWidget {
  const KeyboardDismissOnScroll({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        // Only user drags dismiss the keyboard — the framework's own
        // ensureVisible scroll (revealing a focused field above the
        // keyboard) is programmatic, has null dragDetails, and must not
        // steal focus from the field being edited.
        if (notification.dragDetails == null) return false;
        FocusScope.of(context).unfocus();
        return false;
      },
      child: child,
    );
  }
}
