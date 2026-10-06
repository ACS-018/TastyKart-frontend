import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/food_item.dart';
import '../../../services/firestore_service.dart';
import '../../../state/diet_filter_controller.dart';
import '../../../state/home_filter_controller.dart';
import '../../../utils/app_feedback.dart';
import '../../restaurant/restaurant_menu_screen.dart';
import '../all_food_items_screen.dart';

class FeaturedList extends StatelessWidget {
  const FeaturedList({super.key});

  @override
  Widget build(BuildContext context) {
    final diet = DietFilterScope.of(context);
    final filters = HomeFilterScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([diet, filters]),
      builder: (context, _) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirestoreService.activeFoodItems(availableOnly: true),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();

            final items = (snapshot.data?.docs ?? [])
                .map(FoodItem.fromDoc)
                .where((f) => f.name.isNotEmpty)
                .where(diet.matchesFood)
                .where(filters.matchesFood)
                .take(12)
                .toList();

            if (items.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Are You Here?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            AppFeedback.light();
                            AllFoodItemsScreen.open(
                              context,
                              dietMode: diet.mode,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text(
                                  'See All',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 12,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      FeaturedFoodCard(item: items[index]),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class FeaturedFoodCard extends StatelessWidget {
  const FeaturedFoodCard({super.key, required this.item});

  final FoodItem item;

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        item.discountedPrice > 0 && item.discountedPrice < item.price;
    final discountPct = hasDiscount
        ? (((item.price - item.discountedPrice) / item.price) * 100).round()
        : 0;
    final displayPrice = hasDiscount ? item.discountedPrice : item.price;
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
                  // Positioned(
                  //   top: 10,
                  //   right: 10,
                  //   child: FavoriteRestaurantButton(restaurant: restaurant),
                  // ),
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
