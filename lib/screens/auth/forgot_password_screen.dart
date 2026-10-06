import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/color_constants.dart';
import '../../global_widgets/app_button.dart';
import '../../global_widgets/app_text_field.dart';
import '../../global_widgets/loading_overlay.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';
import 'components/auth_header.dart';

/// Forgot password — Firebase email reset link only.
///
/// Phone OTP is not used here: Firebase password reset is email-based, and
/// Phone Auth must be enabled separately for SMS login (not for resetting
/// email/password accounts).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;
  bool _submittedOnce = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _onSendEmailReset() async {
    if (_isLoading) return;

    setState(() => _submittedOnce = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _dismissKeyboard();
    setState(() => _isLoading = true);

    try {
      await AuthService.sendPasswordResetEmail(_emailCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder.',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      Navigator.of(context).pop();
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

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email.toLowerCase())) {
      return 'Enter a valid email address';
    }
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
    final double fieldSpacing = r.responsive(
      mobile: 16.0,
      tablet: 18.0,
      desktop: 20.0,
    );

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: false,
          child: ColoredBox(
            color: AppColors.primary,
            child: SafeArea(
              bottom: false,
              child: ColoredBox(
                color: AppColors.background,
                child: Column(
                  children: [
                    const AuthHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPad,
                        ),
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
                                SizedBox(height: fieldSpacing * 2),
                                Text(
                                  'Forgot Password?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: r.responsive(
                                      mobile: 22.0,
                                      tablet: 24.0,
                                      desktop: 26.0,
                                    ),
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                SizedBox(height: fieldSpacing * 0.5),
                                Text(
                                  'Enter your account email and we\'ll send a\nFirebase password reset link.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: r.responsive(
                                      mobile: 13.0,
                                      tablet: 14.0,
                                      desktop: 14.0,
                                    ),
                                    color: AppColors.textMedium,
                                    height: 1.5,
                                  ),
                                ),
                                SizedBox(height: fieldSpacing * 2),
                                AppTextField(
                                  label: 'Email',
                                  hint: 'you@example.com',
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  prefixIcon: Icons.mail_outline_rounded,
                                  validator: _validateEmail,
                                ),
                                SizedBox(height: fieldSpacing * 2),
                                AppButton(
                                  label: 'Send Reset Link',
                                  onPressed:
                                      _isLoading ? null : _onSendEmailReset,
                                ),
                                SizedBox(height: fieldSpacing),
                                Center(
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => Navigator.of(context).pop(),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                    ),
                                    child: const Text(
                                      'Back to Sign In',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
