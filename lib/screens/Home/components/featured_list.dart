import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/food_item.dart';
import '../../../services/firestore_service.dart';
import '../../restaurant/restaurant_menu_screen.dart';

class FeaturedList extends StatelessWidget {
  const FeaturedList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService.activeFoodItems(availableOnly: true),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final items = (snapshot.data?.docs ?? [])
            .map(FoodItem.fromDoc)
            .where((f) => f.name.isNotEmpty)
            .toList();

        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Are You Here?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: const Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) =>
                  FeaturedFoodCard(item: items[index]),
            ),
          ],
        );
      },
    );
  }
}

class FeaturedFoodCard extends StatefulWidget {
  const FeaturedFoodCard({super.key, required this.item});

  final FoodItem item;

  @override
  State<FeaturedFoodCard> createState() => _FeaturedFoodCardState();
}

class _FeaturedFoodCardState extends State<FeaturedFoodCard> {
  bool _isFavorite = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDiscount =
        item.discountedPrice > 0 && item.discountedPrice < item.price;
    final discountPct = hasDiscount
        ? (((item.price - item.discountedPrice) / item.price) * 100).round()
        : 0;
    final displayPrice = hasDiscount ? item.discountedPrice : item.price;
    final cuisineLabel = [
      if (item.categoryName.isNotEmpty) item.categoryName,
      ...item.tags.where((t) => t != 'bestseller' && t != 'nonveg' && t != 'veg'),
    ].take(2).join(' · ');

    return GestureDetector(
      onTap: () {
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image ────────────────────────────────────────────────────────
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
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFF5F5F5),
                          child: const Icon(
                            Icons.fastfood_rounded,
                            size: 48,
                            color: Color(0xFFBDBDBD),
                          ),
                        ),
                      )
                    : Container(
                        color: const Color(0xFFF5F5F5),
                        child: const Icon(
                          Icons.fastfood_rounded,
                          size: 48,
                          color: Color(0xFFBDBDBD),
                        ),
                      ),

                // Discount ribbon
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

                // Favorite button
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => setState(() => _isFavorite = !_isFavorite),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color: _isFavorite
                            ? AppColors.primary
                            : const Color(0xFF6B6B6B),
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

          // ── Details ──────────────────────────────────────────────────────
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
}
