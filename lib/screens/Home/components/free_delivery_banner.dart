import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/admin_models.dart';
import '../../../services/firestore_service.dart';

class FreeDeliveryBanner extends StatelessWidget {
  const FreeDeliveryBanner({
    super.key,
    this.showHorizontalMargin = true,
    this.verticalPadding = 6,
  });

  final bool showHorizontalMargin;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirestoreService.adminSettings(),
      builder: (context, snap) {
        // Read live threshold — same source as restaurant menu screen.
        final charges = PlatformCharges.fromSettingsDoc(snap.data);
        final threshold = charges.freeDeliveryThreshold;

        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: showHorizontalMargin ? 16 : 0,
            vertical: verticalPadding,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB32B2C), Color(0xFF8B1F20)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // ── Icon badge ───────────────────────────────────────────
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🛵', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 12),
              // ── Text — threshold from Firestore ─────────────────────
              Expanded(
                child: Text(
                  'Free Delivery With Subscription\nAbove ₹$threshold At Your current Location',
                  style: const TextStyle(
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
      },
    );
  }
}
