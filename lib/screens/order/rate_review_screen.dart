import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';
import '../Home/home_screen.dart';

class RateReviewScreen extends StatefulWidget {
  const RateReviewScreen({super.key, this.orderId = '#12345'});

  final String orderId;

  @override
  State<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends State<RateReviewScreen> {
  int _stars = 4;
  int? _tip;
  final _feedbackCtrl = TextEditingController();

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => Navigator.pop(context),
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
                      'Rate Us',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'How was your homemade meal?',
                      style: TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
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
                        'Rate & Review',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rate Order: ${widget.orderId}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Feedback',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _feedbackCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Your feedback helps us',
                          filled: true,
                          fillColor: const Color(0xFFF7F7F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Rate Delivery',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(5, (i) {
                          final filled = i < _stars;
                          return GestureDetector(
                            onTap: () => setState(() => _stars = i + 1),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.star_rounded,
                                size: 36,
                                color: filled
                                    ? const Color(0xFFFFB300)
                                    : const Color(0xFFDDDDDD),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Thanks Him By Leaving Tip',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [10, 20, 30].map((amount) {
                          final selected = _tip == amount;
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _tip = selected ? null : amount,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : const Color(0xFFDDDDDD),
                                  ),
                                ),
                                child: Text(
                                  '+₹$amount',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? AppColors.white
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final cart = CartScope.maybeOf(context);
                    try {
                      await FirestoreService.addReview({
                        'customerName': cart?.customerName ?? 'Guest User',
                        'customerId': cart?.customerId,
                        'rating': _stars,
                        'comment': _feedbackCtrl.text.trim(),
                        'type': 'delivery',
                        'status': 'published',
                        'orderId': widget.orderId,
                      });
                    } catch (_) {
                      // Keep UX flowing even if reviews write is blocked later.
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (_) => false,
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
                    'Submit Review',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
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
