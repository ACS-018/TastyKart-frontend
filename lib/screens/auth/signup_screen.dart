import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSignup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms to continue.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.signup(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // AuthGate switches to Home when auth state updates.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlySignupError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlySignupError(Object e) => AuthService.messageFromError(e);

  Future<void> _onGoogle() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithGoogle();
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
                leading: const BackButton(color: AppColors.textDark),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: topPad),

                            // ── Header ────────────────────────────────────
                            const AuthHeader(),

                            SizedBox(height: fieldSpacing * 2),

                            // ── Full name ─────────────────────────────────
                            AppTextField(
                              label: 'Full Name',
                              hint: 'John Doe',
                              controller: _nameCtrl,
                              keyboardType: TextInputType.name,
                              prefixIcon: Icons.person_outline_rounded,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Name is required';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldSpacing),

                            // ── Email ─────────────────────────────────────
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

                            SizedBox(height: fieldSpacing),

                            // ── Password ──────────────────────────────────
                            AppTextField(
                              label: 'Password',
                              hint: '••••••••',
                              controller: _passwordCtrl,
                              isPassword: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Password is required';
                                }
                                if (v.length < 6) {
                                  return 'At least 6 characters';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldSpacing),

                            // ── Confirm password ──────────────────────────
                            AppTextField(
                              label: 'Confirm Password',
                              hint: '••••••••',
                              controller: _confirmCtrl,
                              isPassword: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Please confirm your password';
                                }
                                if (v != _passwordCtrl.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldSpacing),

                            // ── Terms checkbox ────────────────────────────
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
                                    onChanged: (v) => setState(
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

                            // ── Sign up button ────────────────────────────
                            AppButton(
                              label: 'Create Account',
                              onPressed: _onSignup,
                              isLoading: _isLoading,
                            ),

                            SizedBox(height: fieldSpacing * 1.5),

                            // ── Social auth ───────────────────────────────
                            SocialAuthRow(onGoogleTap: _onGoogle),

                            SizedBox(height: fieldSpacing * 2),

                            // ── Footer link ───────────────────────────────
                            AuthFooterLink(
                              question: 'Already have an account?',
                              actionLabel: 'Sign In',
                              onTap: () => Navigator.of(context).pop(),
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
