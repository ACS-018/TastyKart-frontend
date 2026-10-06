import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/color_constants.dart';

/// Consistent haptics + snackbars without changing screen layouts.
class AppFeedback {
  AppFeedback._();

  static void light() => HapticFeedback.lightImpact();

  static void selection() => HapticFeedback.selectionClick();

  static void success() => HapticFeedback.mediumImpact();

  static void error() => HapticFeedback.heavyImpact();

  static void showSnackBar(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          duration: duration,
        ),
      );
  }

  static void showSuccess(BuildContext context, String message) {
    success();
    showSnackBar(
      context,
      message: message,
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 2),
    );
  }

  static void showError(BuildContext context, String message) {
    error();
    showSnackBar(
      context,
      message: message,
      backgroundColor: AppColors.error,
    );
  }
}
