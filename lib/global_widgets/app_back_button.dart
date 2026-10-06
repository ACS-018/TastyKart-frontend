import 'package:flutter/material.dart';
import '../constants/color_constants.dart';

/// Standard back button used across the entire app.
/// Always uses [Icons.arrow_back_ios_new_rounded] at size 20.
///
/// Drop-in for AppBar.leading or any row that needs a back action.
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.color = AppColors.white,
    this.onPressed,
  });

  /// Icon colour — defaults to white (for primary-coloured headers).
  final Color color;

  /// Override the tap handler. When null, calls [Navigator.pop].
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      icon: Icon(
        Icons.arrow_back_ios_new_rounded,
        color: color,
        size: 20,
      ),
    );
  }
}
