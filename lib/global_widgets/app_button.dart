import 'package:flutter/material.dart';
import '../constants/color_constants.dart';
import '../utils/responsive.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.width,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);

    final double height = r.responsive(mobile: 52, tablet: 56, desktop: 58);
    final double fontSize = r.responsive(mobile: 15, tablet: 16, desktop: 17);
    final double radius = r.responsive(mobile: 25, tablet: 32, desktop: 34);

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: isOutlined
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
              child: _child(fontSize),
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
              child: _child(fontSize),
            ),
    );
  }

  Widget _child(double fontSize) {
    if (isLoading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
        ),
      );
    }
    return Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: isOutlined ? AppColors.primary : AppColors.white,
      ),
    );
  }
}
