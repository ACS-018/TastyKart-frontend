import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../constants/color_constants.dart';
import '../../../constants/image_constants.dart';
import '../../../models/customer_account.dart';
import '../../../services/firestore_service.dart';
import '../../../services/subscription_service.dart';
import '../../../utils/app_feedback.dart';

// ── Plan model ────────────────────────────────────────────────────────────────

class _SubscriptionPlan {
  final String id;
  final String name;
  final int price;
  final String duration;
  final List<String> benefits;
  final Color accentColor;

  const _SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    required this.benefits,
    required this.accentColor,
  });

  factory _SubscriptionPlan.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final rawBenefits = d['benefits'] as List? ?? [];
    final benefits = rawBenefits
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    Color accent = AppColors.primary;
    final colorHex = d['color'] as String? ?? '';
    if (colorHex.isNotEmpty) {
      try {
        final hex = colorHex.replaceFirst('#', '');
        final parsed = int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
        accent = Color(parsed);
      } catch (_) {}
    }

    return _SubscriptionPlan(
      id: d['id'] as String? ?? doc.id,
      name: d['name'] as String? ?? 'Subscription',
      price: (d['price'] as num? ?? 0).toInt(),
      duration: d['duration'] as String? ?? 'monthly',
      benefits: benefits,
      accentColor: accent,
    );
  }

  String get durationLabel {
    switch (duration.toLowerCase()) {
      case 'monthly':
        return 'mo';
      case 'yearly':
        return 'yr';
      case 'weekly':
        return 'wk';
      default:
        return duration;
    }
  }
}

// ── Card entry point ──────────────────────────────────────────────────────────

/// Home subscription promo card.
/// Hides itself when the user already has an active subscription.
class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<List<DocumentSnapshot>>(
      stream: FirestoreService.activePlans(),
      builder: (context, planSnap) {
        if (!planSnap.hasData || planSnap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final plan = _SubscriptionPlan.fromDoc(planSnap.data!.first);

        // If user is signed-in, check whether they are already subscribed.
        if (uid == null) {
          return _SubscriptionCardView(plan: plan);
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirestoreService.watchCustomerDoc(uid),
          builder: (context, custSnap) {
            if (custSnap.hasData && custSnap.data!.exists) {
              final account = CustomerAccount.fromMap(
                uid,
                custSnap.data!.data() as Map<String, dynamic>? ?? {},
              );
              // Hide the promo card for already-subscribed users.
              if (account.hasActiveSubscription) return const SizedBox.shrink();
            }
            return _SubscriptionCardView(plan: plan);
          },
        );
      },
    );
  }
}

// ── Card UI ───────────────────────────────────────────────────────────────────

class _SubscriptionCardView extends StatelessWidget {
  const _SubscriptionCardView({required this.plan});

  final _SubscriptionPlan plan;

  Future<void> _openSheet(BuildContext context) async {
    AppFeedback.light();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SubscriptionSheet(plan: plan),
    );
  }

  @override
  Widget build(BuildContext context) {
    final benefitLine = plan.benefits.isNotEmpty
        ? plan.benefits.first
        : 'Free Deliveries Above';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Brand name + tagline + illustration ──────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A1A),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Food You Love , Delivered Fast',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  height: 80,
                  child: Image.asset(
                    AppImages.logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.fastfood_rounded,
                      size: 56,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Eat More / Save More ─────────────────────────────────────
            const Text(
              'Eat More',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                height: 1.3,
              ),
            ),
            const Text(
              'Save More',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                height: 1.3,
              ),
            ),

            const SizedBox(height: 10),

            // ── Benefit line ─────────────────────────────────────────────
            Text(
              benefitLine,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
              ),
            ),

            const SizedBox(height: 14),

            // ── Price + location label ────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Text(
                    '₹${plan.price}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      height: 1.1,
                    ),
                  ),
                  const Text(
                    'At This Location',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Full-width Subscribe button ──────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _openSheet(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Subscribe',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _SubscriptionSheet extends StatefulWidget {
  const _SubscriptionSheet({required this.plan});
  final _SubscriptionPlan plan;

  @override
  State<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<_SubscriptionSheet> {
  final SubscriptionService _service = SubscriptionService();
  bool _loading = false;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      AppFeedback.showError(context, 'Please sign in to subscribe');
      return;
    }
    if (_loading) return;

    setState(() => _loading = true);
    AppFeedback.light();

    final result = await _service.purchase(
      planId: widget.plan.id,
      planName: widget.plan.name,
      planPrice: widget.plan.price,
      planDuration: widget.plan.duration,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.isSuccess) {
      Navigator.pop(context); // close sheet
      AppFeedback.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 ${widget.plan.name} activated! Enjoy free delivery.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (result.isPending) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment received (ID: ${result.razorpayPaymentId ?? ''}).'
            ' Subscription will activate shortly.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Cancelled — just close sheet silently.
    if (result.status == SubscriptionPaymentStatus.cancelled) {
      Navigator.pop(context);
      return;
    }

    // Failed
    final reason = result.reason ?? '';
    final message = reason == 'razorpay_key_not_configured'
        ? 'Payment not configured. Add your Razorpay key in AppConstants.'
        : reason == 'not_signed_in'
        ? 'Please sign in to subscribe'
        : 'Payment failed: $reason';
    AppFeedback.showError(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan name + price
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${plan.price}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'per ${plan.durationLabel}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A8A8A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Benefits from Firestore
                if (plan.benefits.isNotEmpty) ...[
                  const Text(
                    'What you get',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4A4A4A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...plan.benefits.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 11,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              b,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4A4A4A),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // Subscribe button (Razorpay)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _subscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.5,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            'Subscribe for ₹${plan.price} / ${plan.durationLabel}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
