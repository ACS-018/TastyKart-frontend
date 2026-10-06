import 'package:flutter/material.dart';

import '../constants/color_constants.dart';

/// Centered loading / error / empty slot — same footprint as existing `Center` widgets.
class AsyncStateMessage extends StatelessWidget {
  const AsyncStateMessage({
    super.key,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  const AsyncStateMessage.loading({super.key})
      : message = '',
        icon = null,
        actionLabel = null,
        onAction = null,
        loading = true;

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 44, color: AppColors.textLight),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B6B6B),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
