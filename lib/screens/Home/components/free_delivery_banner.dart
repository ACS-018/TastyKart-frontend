import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';

class FreeDeliveryBanner extends StatelessWidget {
  const FreeDeliveryBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB32B2C), Color(0xFF8B1F20)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // ── Icon badge ─────────────────────────────────────────────────────
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🛵', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          // ── Text ───────────────────────────────────────────────────────────
          const Expanded(
            child: Text(
              'Free Delivery With Subscription\nAbove ₹49 At Your current Location',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
