import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/color_constants.dart';
import '../../models/food_item.dart';
import '../../services/firestore_service.dart';
import '../../state/diet_filter_controller.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_navigation.dart';
import '../restaurant/restaurant_menu_screen.dart';

/// Full list of "Are You Here?" food items.
class AllFoodItemsScreen extends StatelessWidget {
  const AllFoodItemsScreen({super.key, this.dietMode = DietMode.nonVeg});

  final DietMode dietMode;

  static Future<void> open(
    BuildContext context, {
    DietMode dietMode = DietMode.nonVeg,
  }) {
    return AppNavigation.push(
      context,
      AllFoodItemsScreen(dietMode: dietMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Are You Here?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.white,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.activeFoodItems(availableOnly: true),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final items = (snapshot.data?.docs ?? [])
              .map(FoodItem.fromDoc)
              .where((f) => f.name.isNotEmpty)
              .where((f) {
                if (dietMode == DietMode.veg) return f.isVeg;
                return true;
              })
              .toList();

          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No items available right now.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B6B6B),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _AllFoodCard(item: items[index]),
          );
        },
      ),
    );
  }
}

class _AllFoodCard extends StatelessWidget {
  const _AllFoodCard({required this.item});

  final FoodItem item;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = item.hasDiscount;
    final discountPct = item.discountPercent;
    final displayPrice = item.displayPrice;
    final cuisineLabel = [
      if (item.categoryName.isNotEmpty) item.categoryName,
      ...item.tags.where(
        (t) => t != 'bestseller' && t != 'nonveg' && t != 'veg',
      ),
    ].take(2).join(' · ');

    return GestureDetector(
      onTap: () {
        AppFeedback.light();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantMenuScreen(
              restaurantId: item.restaurantId,
              restaurantName: item.restaurantName,
              highlightItem: item,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ─────────────────────────────────────────────────────
            SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.image.isNotEmpty
                      ? Image.network(
                          item.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                  if (hasDiscount)
                    Positioned(
                      top: 12,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Flat $discountPct% Off',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  // Rating badge
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: AppColors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Info ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (cuisineLabel.isNotEmpty)
                    Text(
                      cuisineLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B6B6B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '₹$displayPrice For One',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: Color(0xFF6B6B6B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${item.preparationTime} Min',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '|',
                        style: TextStyle(color: Color(0xFFCCCCCC)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.restaurantName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B6B6B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: const Icon(
        Icons.fastfood_rounded,
        size: 48,
        color: Color(0xFFBDBDBD),
      ),
    );
  }
}
