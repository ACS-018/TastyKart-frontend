import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/color_constants.dart';
import '../../global_widgets/app_back_button.dart';
import '../../global_widgets/app_button.dart';
import '../../global_widgets/app_text_field.dart';
import '../../global_widgets/loading_overlay.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';
import 'components/auth_footer_link.dart';
import 'components/auth_header.dart';
import 'components/social_auth_row.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _agreedToTerms = false;
  bool _submittedOnce = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _goToAuthenticatedHome() {
    if (!mounted) return;
    // Signup was pushed on top of AuthGate; pop so AuthGate can show Home.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _onSignup() async {
    if (_isLoading) return;

    setState(() => _submittedOnce = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Please accept the terms to continue.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      return;
    }

    _dismissKeyboard();
    setState(() => _isLoading = true);

    try {
      await AuthService.signup(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Account created successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      _goToAuthenticatedHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AuthService.messageFromError(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onGoogle() async {
    if (_isLoading) return;

    _dismissKeyboard();
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithGoogle();
      if (!mounted) return;
      _goToAuthenticatedHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AuthService.messageFromError(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Name is required';
    if (name.length < 2) return 'Enter your full name';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email.toLowerCase())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'At least 6 characters';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);

    final double maxWidth = r.responsive(
      mobile: double.infinity,
      tablet: 480.0,
      desktop: 440.0,
    );
    final double horizontalPad = r.responsive(
      mobile: 24.0,
      tablet: 32.0,
      desktop: 40.0,
    );
    final double topPad = r.responsive(
      mobile: 32.0,
      tablet: 48.0,
      desktop: 64.0,
    );
    final double fieldSpacing = r.responsive(
      mobile: 16.0,
      tablet: 18.0,
      desktop: 20.0,
    );
    final double checkboxFontSize = r.responsive(
      mobile: 12.0,
      tablet: 13.0,
      desktop: 14.0,
    );

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        appBar: r.isMobile
            ? null
            : AppBar(
                backgroundColor: AppColors.primary,
                elevation: 0,
                leading: const AppBackButton(),
              ),
        body: SafeArea(
          top: false,
          child: ColoredBox(
            color: AppColors.primary,
            child: SafeArea(
              bottom: false,
              child: ColoredBox(
                color: AppColors.background,
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: _submittedOnce
                            ? AutovalidateMode.onUserInteraction
                            : AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: topPad),
                            const AuthHeader(),
                            SizedBox(height: fieldSpacing * 2),
                            AppTextField(
                              label: 'Full Name',
                              hint: 'John Doe',
                              controller: _nameCtrl,
                              keyboardType: TextInputType.name,
                              prefixIcon: Icons.person_outline_rounded,
                              validator: _validateName,
                            ),
                            SizedBox(height: fieldSpacing),
                            AppTextField(
                              label: 'Email',
                              hint: 'you@example.com',
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.mail_outline_rounded,
                              validator: _validateEmail,
                            ),
                            SizedBox(height: fieldSpacing),
                            AppTextField(
                              label: 'Password',
                              hint: '••••••••',
                              controller: _passwordCtrl,
                              isPassword: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: _validatePassword,
                            ),
                            SizedBox(height: fieldSpacing),
                            AppTextField(
                              label: 'Confirm Password',
                              hint: '••••••••',
                              controller: _confirmCtrl,
                              isPassword: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: _validateConfirm,
                            ),
                            SizedBox(height: fieldSpacing),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _agreedToTerms,
                                    activeColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: _isLoading
                                        ? null
                                        : (v) => setState(
                                            () => _agreedToTerms = v ?? false,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      text: 'I agree to the ',
                                      style: TextStyle(
                                        fontSize: checkboxFontSize,
                                        color: AppColors.textMedium,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'Terms of Service',
                                          style: TextStyle(
                                            fontSize: checkboxFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const TextSpan(text: ' and '),
                                        TextSpan(
                                          text: 'Privacy Policy',
                                          style: TextStyle(
                                            fontSize: checkboxFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: fieldSpacing * 1.5),
                            AppButton(
                              label: 'Create Account',
                              onPressed: _isLoading ? null : _onSignup,
                            ),
                            SizedBox(height: fieldSpacing * 1.5),
                            SocialAuthRow(
                              onGoogleTap: _isLoading ? null : _onGoogle,
                            ),
                            SizedBox(height: fieldSpacing * 2),
                            AuthFooterLink(
                              question: 'Already have an account?',
                              actionLabel: 'Sign In',
                              onTap: _isLoading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                            ),
                            SizedBox(height: topPad / 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
