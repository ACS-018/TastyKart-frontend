import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../state/cart_controller.dart';
import '../../widgets/order_tracking_map.dart';
import '../Home/home_screen.dart';
import '../order/delivered_screen.dart';

class TrackOrderScreen extends StatelessWidget {
  const TrackOrderScreen({super.key, this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    final resolvedId = orderId ??
        'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final address =
        cart.selectedAddress?.fullAddress ?? 'No delivery address selected';
    final price = cart.grandTotal == 0 ? 0 : cart.grandTotal;
    final serves = cart.itemCount == 0 ? 1 : cart.itemCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 16,
              bottom: 18,
            ),
            color: AppColors.primary,
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    cart.clear();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (_) => false,
                    );
                  },
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track Your Order',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Order Your Daily Meal With Us',
                      style: TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const Text(
                  'Track Your Order',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Real-time updates on your meal preparation.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B)),
                ),
                const SizedBox(height: 16),
                Stack(
                  children: [
                    OrderTrackingMap(
                      height: 280,
                      destinationLat: cart.selectedAddress?.lat,
                      destinationLng: cart.selectedAddress?.lng,
                      destinationAddress: cart.selectedAddress?.fullAddress,
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Order ID #$resolvedId',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              'Serves $serves',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B6B6B),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '₹$price',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '8:30 PM Delivery Time',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0xFFFFE8E8),
                            child: Icon(
                              Icons.delivery_dining_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rider Ramesh',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Delivery Boy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B6B6B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE8E8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () {},
                              icon: const Icon(
                                Icons.phone_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      final id = resolvedId;
                      cart.clear();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeliveredScreen(orderId: id),
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
                      'Order Delivered',
                      style: TextStyle(
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
