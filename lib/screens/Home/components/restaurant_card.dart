import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/food_item.dart';
import '../../restaurant/restaurant_menu_screen.dart';

export '../../../models/food_item.dart';

/// Food item card (featured / favourites). Opens restaurant by id when available.
class FoodCard extends StatelessWidget {
  const FoodCard({super.key, required this.item});

  final FoodItem item;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = item.hasDiscount;
    final discount = hasDiscount ? '${item.discountPercent}% Off' : null;

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
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: item.image.isNotEmpty
                      ? Image.network(
                          item.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFF5F5F5),
                            child: const Icon(Icons.fastfood_rounded),
                          ),
                        )
                      : Container(
                          color: const Color(0xFFF5F5F5),
                          child: const Icon(Icons.fastfood_rounded),
                        ),
                ),
                if (discount != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      color: Colors.black.withOpacity(0.55),
                      child: Text(
                        discount,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.restaurantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${item.displayPrice}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
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
