import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../utils/responsive.dart';

class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.actionLabel,
    required this.onTap,
  });

  final String question;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    final double fontSize = r.responsive(
      mobile: 13.0,
      tablet: 14.0,
      desktop: 15.0,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          question,
          style: TextStyle(fontSize: fontSize, color: AppColors.textMedium),
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            ' $actionLabel',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
