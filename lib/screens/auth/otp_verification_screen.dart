import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../global_widgets/app_button.dart';
import '../../global_widgets/loading_overlay.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';
import 'components/auth_header.dart';
import 'reset_password_screen.dart';

enum OtpPurpose { resetPassword, login }

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.phone,
    required this.verificationId,
    this.purpose = OtpPurpose.resetPassword,
    this.autoVerified = false,
  });

  final String phone;
  final String verificationId;
  final OtpPurpose purpose;
  final bool autoVerified;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _otpLength = 6;
  static const int _resendSeconds = 60;

  final List<TextEditingController> _controllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );

  bool _isLoading = false;
  int _secondsLeft = _resendSeconds;
  Timer? _timer;
  late String _verificationId;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _startCountdown();
    if (widget.autoVerified) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goNextAfterAuth());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _goNextAfterAuth() async {
    if (!mounted) return;
    if (widget.purpose == OtpPurpose.resetPassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
    }
    // login purpose: AuthGate will open Home automatically.
  }

  Future<void> _onNext() async {
    if (widget.autoVerified) {
      await _goNextAfterAuth();
      return;
    }
    if (_otp.length < _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the complete 6-digit OTP.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.confirmPhoneOtp(
        verificationId: _verificationId,
        smsCode: _otp,
      );
      if (!mounted) return;
      await _goNextAfterAuth();
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

  Future<void> _onResend() async {
    if (_secondsLeft > 0) return;
    setState(() => _isLoading = true);
    await AuthService.verifyPhoneNumber(
      phoneE164: widget.phone,
      onCodeSent: (id) {
        _verificationId = id;
        if (!mounted) return;
        setState(() => _isLoading = false);
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes.first.requestFocus();
        _startCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP resent'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onError: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthService.messageFromError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _onDigitChanged(String value, int index) {
    if (value.length == 1 && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
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
                        padding:
                            EdgeInsets.symmetric(horizontal: horizontalPad),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: fieldSpacing * 2),
                              Text(
                                'OTP Verification',
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
                                'Enter the code sent to\n${widget.phone}',
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(_otpLength, (i) {
                                  return SizedBox(
                                    width: 48,
                                    child: TextField(
                                      controller: _controllers[i],
                                      focusNode: _focusNodes[i],
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      maxLength: 1,
                                      decoration: InputDecoration(
                                        counterText: '',
                                        filled: true,
                                        fillColor: AppColors.inputFill,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onChanged: (v) => _onDigitChanged(v, i),
                                    ),
                                  );
                                }),
                              ),
                              SizedBox(height: fieldSpacing * 2),
                              AppButton(
                                label: 'Verify OTP',
                                onPressed: _isLoading ? null : _onNext,
                              ),
                              SizedBox(height: fieldSpacing),
                              TextButton(
                                onPressed: _secondsLeft > 0 ? null : _onResend,
                                child: Text(
                                  _secondsLeft > 0
                                      ? 'Resend OTP in $_secondsLeft s'
                                      : 'Resend OTP',
                                  style: TextStyle(
                                    color: _secondsLeft > 0
                                        ? AppColors.textLight
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
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
    );
  }
}
