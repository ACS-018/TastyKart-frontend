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
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // AuthGate listens to authStateChanges and opens Home.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyAuthError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyAuthError(Object e) => AuthService.messageFromError(e);

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

    // Content max-width: full on mobile, capped on tablet/desktop
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
      mobile: 40.0,
      tablet: 60.0,
      desktop: 80.0,
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
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // ── Header (full-width, no padding) ─────────────────────
                      const AuthHeader(),

                      // ── Rest of form (padded) ────────────────────────────────
                      Padding(
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
                                // ── Email ──────────────────────────────────────
                                AppTextField(
                                  label: 'Email',
                                  hint: 'you@example.com',
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  prefixIcon: Icons.mail_outline_rounded,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty)
                                      return 'Email is required';
                                    if (!v.contains('@'))
                                      return 'Enter a valid email';
                                    return null;
                                  },
                                ),

                                SizedBox(height: fieldSpacing),

                                // ── Password ────────────────────────────────────────
                                AppTextField(
                                  label: 'Password',
                                  hint: '••••••••',
                                  controller: _passwordCtrl,
                                  isPassword: true,
                                  prefixIcon: Icons.lock_outline_rounded,
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Password is required';
                                    if (v.length < 6)
                                      return 'At least 6 characters';
                                    return null;
                                  },
                                ),

                                // ── Remember me + Forgot password ─────────────────────
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Remember me
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Checkbox(
                                          value: _rememberMe,
                                          onChanged: (value) {
                                            setState(() {
                                              _rememberMe = value ?? false;
                                            });
                                          },
                                          activeColor: AppColors.primary,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        Text(
                                          'Remember me',
                                          style: TextStyle(
                                            fontSize: r.responsive(
                                              mobile: 13.0,
                                              tablet: 14.0,
                                              desktop: 14.0,
                                            ),
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Forgot password
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ForgotPasswordScreen(),
                                          ),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 4,
                                        ),
                                      ),
                                      child: Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          fontSize: r.responsive(
                                            mobile: 13.0,
                                            tablet: 14.0,
                                            desktop: 14.0,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                SizedBox(height: fieldSpacing),

                                // ── Login button ────────────────────────────────────
                                AppButton(
                                  label: 'Sign In',
                                  onPressed: _onLogin,
                                  isLoading: _isLoading,
                                ),

                                SizedBox(height: fieldSpacing * 0.5),
                                AuthFooterLink(
                                  question: "If you don't have account",
                                  actionLabel: 'Create Account',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SignupScreen(),
                                    ),
                                  ),
                                ),
                                SizedBox(height: fieldSpacing * 0.5),
                                SocialAuthRow(onGoogleTap: _onGoogle),

                                SizedBox(height: fieldSpacing * 2),

                                // ── Footer link ─────────────────────────────────────
                                SizedBox(height: topPad / 2),
                              ],
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
      ),
    );
  }
}
