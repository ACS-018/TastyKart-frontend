import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../checkout/track_order_screen.dart';

class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Food image ──────────────────────────────────────────────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('🍛', style: TextStyle(fontSize: 32)),
              ),
            ),
            const SizedBox(width: 12),

            // ── Order details ───────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Order Is On The Way',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Chicken Biryani',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const Text(
                    'From Biryani Kitchen',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: const [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: Color(0xFF6B6B6B),
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Arriving in 12 Min',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Track Order button ──────────────────────────────────
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TrackOrderScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Track Order',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Delivery person illustration ────────────────────────────────
            const Text('🚴', style: TextStyle(fontSize: 40)),
          ],
        ),
      ),
    );
  }
}
