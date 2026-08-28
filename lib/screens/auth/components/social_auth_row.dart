import 'package:flutter/material.dart';
import 'package:tasty_kart/constants/image_constants.dart';
import '../../../constants/color_constants.dart';
import '../../../utils/responsive.dart';

class SocialAuthRow extends StatelessWidget {
  const SocialAuthRow({super.key, this.onGoogleTap, this.onAppleTap});

  final VoidCallback? onGoogleTap;
  final VoidCallback? onAppleTap;

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    final double iconSize = r.responsive(
      mobile: 22.0,
      tablet: 24.0,
      desktop: 26.0,
    );
    final double btnHeight = r.responsive(
      mobile: 50.0,
      tablet: 54.0,
      desktop: 56.0,
    );
    final double fontSize = r.responsive(
      mobile: 13.0,
      tablet: 14.0,
      desktop: 15.0,
    );

    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or Login With',
                style: TextStyle(
                  fontSize: fontSize,
                  color: AppColors.textLight,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.divider)),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: r.responsive(mobile: 220.0, tablet: 260.0, desktop: 300.0),
            child: _SocialButton(
              label: 'Continue with Google',
              icon: Icons.g_mobiledata_rounded,
              iconSize: iconSize,
              height: btnHeight,
              fontSize: fontSize,
              onTap: onGoogleTap,
            ),
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.iconSize,
    required this.height,
    required this.fontSize,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final double iconSize;
  final double height;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.inputBorder),
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(AppImages.Google, width: iconSize, height: iconSize),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
