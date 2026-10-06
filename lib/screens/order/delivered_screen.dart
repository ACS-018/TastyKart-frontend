import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../constants/image_constants.dart';
import '../../state/cart_controller.dart';
import '../../widgets/app_screen_header.dart';
import 'rate_review_screen.dart';

class DeliveredScreen extends StatefulWidget {
  const DeliveredScreen({
    super.key,
    this.orderId = '',
    this.restaurantId = '',
    this.restaurantName = '',
    this.customerId = '',
    this.customerName = '',
    this.deliveryPartnerId = '',
    this.deliveryPartnerName = '',
  });

  final String orderId;
  final String restaurantId;
  final String restaurantName;
  final String customerId;
  final String customerName;
  final String deliveryPartnerId;
  final String deliveryPartnerName;

  @override
  State<DeliveredScreen> createState() => _DeliveredScreenState();
}

class _DeliveredScreenState extends State<DeliveredScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Delivered',
            subtitle: 'Your homemade meal is delivered.',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                // ── Delivery illustration ──────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                    child: Image.asset(
                      AppImages.delivered,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // ── Order Delivered text ───────────────────────────────
                const SizedBox(height: 28),
                const Text(
                  'Order Delivered!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enjoy your meal 🍽️',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B6B6B)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // ── Rate button pinned at bottom ───────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final cart = CartScope.maybeOf(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RateReviewScreen(
                          orderId: widget.orderId,
                          restaurantId: widget.restaurantId.isNotEmpty
                              ? widget.restaurantId
                              : (cart?.lines.isNotEmpty == true
                                    ? cart!.lines.first.item.restaurantId
                                    : ''),
                          restaurantName: widget.restaurantName.isNotEmpty
                              ? widget.restaurantName
                              : (cart?.primaryRestaurantName ?? ''),
                          customerId: widget.customerId,
                          customerName: widget.customerName,
                          deliveryPartnerId: widget.deliveryPartnerId,
                          deliveryPartnerName: widget.deliveryPartnerName,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Rate Your Experience',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
