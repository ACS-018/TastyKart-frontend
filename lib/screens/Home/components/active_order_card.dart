import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../constants/color_constants.dart';
import '../../../constants/image_constants.dart';
import '../../../models/admin_models.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/app_feedback.dart';
import '../../../utils/app_navigation.dart';
import '../../checkout/track_order_screen.dart';

/// Live "Your order is on the way" card — matches Figma layout.
/// Also detects when a previously-active order becomes cancelled and shows
/// a cancellation bottom-sheet so the user is notified even from the home screen.
class ActiveOrderCard extends StatefulWidget {
  const ActiveOrderCard({super.key});

  @override
  State<ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<ActiveOrderCard> {
  static const _activeStatuses = {
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'out_for_delivery',
    'on_the_way',
    'picked_up',
    'dispatched',
  };

  // Tracks the IDs of orders that were active in the previous stream emission.
  // Used to detect when an active order transitions to cancelled.
  final Set<String> _prevActiveIds = {};

  // Guards against showing the sheet multiple times for the same order.
  final Set<String> _notifiedCancelledIds = {};

  String _etaLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Confirming your order…';
      case 'confirmed':
        return 'Arriving In 25 Min';
      case 'preparing':
      case 'ready':
        return 'Arriving In 15 Min';
      case 'picked_up':
      case 'dispatched':
      case 'out_for_delivery':
      case 'on_the_way':
        return 'Arriving In 12 Min';
      default:
        return 'On the way';
    }
  }

  String _itemName(TkOrder order) {
    if (order.items.isEmpty) return 'Your order';
    final first = order.items.first;
    final name = (first['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return 'Your order';
    if (order.items.length == 1) return name;
    return '$name +${order.items.length - 1} more';
  }

  void _handleSnapshot(List<TkOrder> allOrders) {
    final activeOrders = allOrders
        .where((o) => _activeStatuses.contains(o.status.toLowerCase()))
        .toList();
    final activeIds = activeOrders.map((o) => o.id).toSet();

    // Find orders that were previously active but are now cancelled.
    final newlyCancelledIds = _prevActiveIds.difference(activeIds);
    if (newlyCancelledIds.isNotEmpty) {
      for (final cancelledId in newlyCancelledIds) {
        if (_notifiedCancelledIds.contains(cancelledId)) continue;
        // Find the full order object from allOrders to get details.
        final cancelled = allOrders.where((o) => o.id == cancelledId).toList();
        if (cancelled.isNotEmpty &&
            cancelled.first.status.toLowerCase() == 'cancelled') {
          _notifiedCancelledIds.add(cancelledId);
          // Show the sheet after the frame completes to avoid setState-during-build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showCancelledSheet(cancelled.first);
          });
        }
      }
    }

    // Update tracked set for the next emission.
    _prevActiveIds
      ..clear()
      ..addAll(activeIds);
  }

  void _showCancelledSheet(TkOrder order) {
    AppFeedback.error(); // heavy haptic (strongest available)
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CancelledOrderSheet(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<TkOrder>>(
      stream: FirestoreService.ordersByCustomer(
        uid,
      ).map((snap) => snap.docs.map(TkOrder.fromDoc).toList()),
      builder: (context, snapshot) {
        final allOrders = snapshot.data ?? [];

        // Side-effect: detect cancellations — runs synchronously in builder
        // but defers the UI work to addPostFrameCallback.
        if (snapshot.hasData) _handleSnapshot(allOrders);

        final orders =
            allOrders
                .where((o) => _activeStatuses.contains(o.status.toLowerCase()))
                .toList()
              ..sort((a, b) {
                final aa =
                    a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bb =
                    b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                return bb.compareTo(aa);
              });

        if (orders.isEmpty) return const SizedBox.shrink();
        final order = orders.first;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: GestureDetector(
            onTap: () {
              AppFeedback.light();
              AppNavigation.push(context, TrackOrderScreen(orderId: order.id));
            },
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  // ── Left content ──────────────────────────────────────
                  Padding(
                    // Right padding leaves room for the delivery boy image.
                    padding: const EdgeInsets.fromLTRB(16, 12, 100, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        const Text(
                          'Your Order Is On The Way',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Food thumbnail + name + restaurant + ETA
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Food thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: order.restaurantImage.isNotEmpty
                                    ? Image.network(
                                        order.restaurantImage,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _foodPlaceholder(),
                                      )
                                    : _foodPlaceholder(),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Name + restaurant + ETA
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _itemName(order),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A1A1A),
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    order.restaurantName.isEmpty
                                        ? 'From ${AppConstants.appName}'
                                        : 'From ${order.restaurantName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6B6B6B),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _etaLabel(order.status),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6B6B6B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Track Order button
                        GestureDetector(
                          onTap: () {
                            AppFeedback.light();
                            AppNavigation.push(
                              context,
                              TrackOrderScreen(orderId: order.id),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Text(
                              'Track Order',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Delivery boy image — right side, vertically centred ─
                  Positioned(
                    right: 8,
                    top: 8,
                    bottom: 8,
                    child: Center(
                      child: Image.asset(
                        AppImages.deliveryBoy,
                        width: 85,
                        height: 85,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _foodPlaceholder() {
    return Container(
      color: const Color(0xFFFFE8E8),
      child: const Icon(
        Icons.restaurant_rounded,
        color: AppColors.primary,
        size: 28,
      ),
    );
  }
}

// ── Cancelled order bottom sheet ──────────────────────────────────────────────

class _CancelledOrderSheet extends StatelessWidget {
  const _CancelledOrderSheet({required this.order});

  final TkOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Color(0xFFFFECEC),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_rounded,
              color: AppColors.primary,
              size: 38,
            ),
          ),
          const SizedBox(height: 14),

          const Text(
            'Order Cancelled',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            order.restaurantName.isNotEmpty
                ? 'Your order from ${order.restaurantName} has been cancelled.'
                : 'Your order has been cancelled.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B6B6B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'If you were charged, a refund will be processed shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF9E9E9E),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Order ID chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Order ID: ${order.orderNumber}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF444444),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // View Details button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close sheet
                AppNavigation.push(
                  context,
                  TrackOrderScreen(orderId: order.id),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'View Details',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Dismiss button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Dismiss',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
