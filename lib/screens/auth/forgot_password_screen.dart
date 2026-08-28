import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../global_widgets/app_button.dart';
import '../../global_widgets/app_text_field.dart';
import '../../global_widgets/loading_overlay.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';
import 'components/auth_header.dart';
import 'otp_verification_screen.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isLoading = false;
  bool _usePhone = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSendEmailReset() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.sendPasswordResetEmail(_emailCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Check your inbox.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.messageFromError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onSendPhoneOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    final phone = AuthService.toE164Phone(_phoneCtrl.text.trim());

    await AuthService.verifyPhoneNumber(
      phoneE164: phone,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              phone: phone,
              verificationId: verificationId,
              purpose: OtpPurpose.resetPassword,
            ),
          ),
        );
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthService.messageFromError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onAutoVerified: (credential) async {
        try {
          await AuthService.signInWithCredential(credential);
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          );
        } catch (e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AuthService.messageFromError(e)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
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
                                  _usePhone
                                      ? 'Enter your phone number and we\'ll send\nan OTP via Firebase.'
                                      : 'Enter your email and we\'ll send a\nFirebase password reset link.',
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
                                if (_usePhone)
                                  AppTextField(
                                    label: 'Phone Number',
                                    hint: '10-digit mobile number',
                                    controller: _phoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    prefixIcon: Icons.phone_outlined,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Phone number is required';
                                      }
                                      if (v.replaceAll(RegExp(r'\D'), '').length <
                                          10) {
                                        return 'Enter a valid phone number';
                                      }
                                      return null;
                                    },
                                  )
                                else
                                  AppTextField(
                                    label: 'Email',
                                    hint: 'you@example.com',
                                    controller: _emailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    prefixIcon: Icons.mail_outline_rounded,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Email is required';
                                      }
                                      if (!v.contains('@')) {
                                        return 'Enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                SizedBox(height: fieldSpacing * 2),
                                AppButton(
                                  label: _usePhone ? 'Send OTP' : 'Send Reset Link',
                                  onPressed: _usePhone
                                      ? _onSendPhoneOtp
                                      : _onSendEmailReset,
                                  isLoading: _isLoading,
                                ),
                                SizedBox(height: fieldSpacing),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _usePhone = !_usePhone),
                                  child: Text(
                                    _usePhone
                                        ? 'Use email instead'
                                        : 'Use phone OTP instead',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Center(
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
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
