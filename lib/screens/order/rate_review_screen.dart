import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../services/firestore_paths.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_screen_header.dart';
import '../Home/home_screen.dart';

class RateReviewScreen extends StatefulWidget {
  const RateReviewScreen({
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
  State<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends State<RateReviewScreen> {
  int _restaurantStars = 0;
  int _partnerStars = 0;
  final _feedbackCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  bool _usableName(String value) {
    final name = value.trim().toLowerCase();
    return name.isNotEmpty &&
        name != 'guest user' &&
        name != 'customer' &&
        name != 'user' &&
        name != 'guest' &&
        !name.startsWith('guest_');
  }

  String _pickName(Map<String, dynamic>? data) {
    if (data == null) return '';
    for (final key in ['name', 'displayName', 'fullName', 'customerName']) {
      final value = (data[key] ?? '').toString();
      if (_usableName(value)) return value.trim();
    }
    return '';
  }

  Future<String> _reviewerName() async {
    if (_usableName(widget.customerName)) return widget.customerName.trim();
    final user = FirebaseAuth.instance.currentUser;
    final customerId = widget.customerId.isNotEmpty
        ? widget.customerId
        : (user?.uid ?? '');
    if (customerId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirestorePaths.customers)
            .doc(customerId)
            .get();
        final stored = _pickName(doc.data());
        if (stored.isNotEmpty) return stored;
      } catch (_) {}
    }
    if (widget.orderId.isNotEmpty) {
      try {
        final order = await FirebaseFirestore.instance
            .collection(FirestorePaths.orders)
            .doc(widget.orderId)
            .get();
        final stored = _pickName(order.data());
        if (stored.isNotEmpty) return stored;
      } catch (_) {}
    }
    if (user != null) {
      final authName = user.displayName?.trim() ?? '';
      if (_usableName(authName)) return authName;
      final email = user.email?.trim() ?? '';
      if (email.contains('@')) return email.split('@').first;
    }
    return 'Customer';
  }

  Future<void> _addPartnerRating(String partnerId, int stars) async {
    final ref = FirebaseFirestore.instance
        .collection(FirestorePaths.deliveryPartners)
        .doc(partnerId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
      final stored = (data['rating'] as num?)?.toDouble() ?? 0;
      final sum = (data['ratingSum'] as num?)?.toDouble() ?? stored * count;
      final nextCount = count + 1;
      final nextSum = sum + stars;
      tx.set(ref, {
        'ratingCount': nextCount,
        'ratingSum': nextSum,
        'rating': nextSum / nextCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_restaurantStars <= 0 && _partnerStars <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please rate the restaurant or the delivery partner'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final reviewer = await _reviewerName();
      final comment = _feedbackCtrl.text.trim();
      if (_restaurantStars > 0) {
        await FirestoreService.addReview({
          'reviewerName': reviewer,
          'customerName': reviewer,
          'customerId': widget.customerId,
          'reviewerRole': 'customer',
          'rating': _restaurantStars,
          'comment': comment,
          'type': 'restaurant',
          'status': 'published',
          'orderId': widget.orderId,
          'restaurantId': widget.restaurantId,
          'restaurantName': widget.restaurantName,
        });
        if (widget.restaurantId.isNotEmpty) {
          await FirestoreService.submitRestaurantRating(
            restaurantId: widget.restaurantId,
            rating: _restaurantStars,
          );
        }
      }
      if (_partnerStars > 0 &&
          (widget.deliveryPartnerId.isNotEmpty ||
              widget.deliveryPartnerName.isNotEmpty)) {
        await FirestoreService.addReview({
          'reviewerName': reviewer,
          'customerName': reviewer,
          'customerId': widget.customerId,
          'reviewerRole': 'customer',
          'rating': _partnerStars,
          'comment': comment,
          'type': 'delivery',
          'status': 'published',
          'orderId': widget.orderId,
          'restaurantId': widget.restaurantId,
          'restaurantName': widget.restaurantName,
          'deliveryPartnerId': widget.deliveryPartnerId,
          'deliveryPartnerName': widget.deliveryPartnerName,
        });
        if (widget.deliveryPartnerId.isNotEmpty) {
          await _addPartnerRating(
            widget.deliveryPartnerId,
            _partnerStars,
          );
        }
      }
    } catch (_) {
      // Rating write failed — still navigate home but inform the user.
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not save your review. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _submitting = false);
      return;
    }

    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Thank you for your feedback!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Rate Us',
            subtitle: 'How was your homemade meal?',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
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
                          color: Colors.black.withValues(alpha: 0.05),
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
                          'Order: ${widget.orderId}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.restaurantName.isEmpty
                              ? 'Restaurant'
                              : widget.restaurantName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StarRow(
                          stars: _restaurantStars,
                          onSelect: (value) =>
                              setState(() => _restaurantStars = value),
                        ),
                        if (widget.deliveryPartnerId.isNotEmpty ||
                            widget.deliveryPartnerName.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            widget.deliveryPartnerName.isEmpty
                                ? 'Delivery partner'
                                : widget.deliveryPartnerName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _StarRow(
                            stars: _partnerStars,
                            onSelect: (value) =>
                                setState(() => _partnerStars = value),
                          ),
                        ],
                        const SizedBox(height: 20),
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
                            hintText:
                                'Share what you liked or what we can improve',
                            filled: true,
                            fillColor: const Color(0xFFF7F7F7),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Submit pinned at bottom ───────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
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

class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars, required this.onSelect});

  final int stars;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = i < stars;
        return GestureDetector(
          onTap: () => onSelect(stars == i + 1 ? 0 : i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.star_rounded,
              size: 40,
              color: filled ? const Color(0xFFFFB300) : const Color(0xFFDDDDDD),
            ),
          ),
        );
      }),
    );
  }
}
