import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/restaurant.dart';
import '../../../services/firestore_service.dart';
import '../../../state/diet_filter_controller.dart';
import '../../../state/home_filter_controller.dart';
import '../../../utils/app_navigation.dart';
import '../../../widgets/async_state_message.dart';
import '../../../widgets/favorite_restaurant_button.dart';
import '../../restaurant/restaurant_menu_screen.dart';
import '../all_restaurants_list_screen.dart';

/// Home restaurant grid — Admin `restaurants` collection.
class RestaurantGrid extends StatefulWidget {
  const RestaurantGrid({super.key, this.maxItems = 6});

  final int maxItems;

  @override
  State<RestaurantGrid> createState() => _RestaurantGridState();
}

class _RestaurantGridState extends State<RestaurantGrid> {
  int _retryToken = 0;

  void _retry() => setState(() => _retryToken++);

  @override
  Widget build(BuildContext context) {
    final diet = DietFilterScope.of(context);
    final filters = HomeFilterScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([diet, filters]),
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Restaurants Near You',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      AppNavigation.push(
                        context,
                        const AllRestaurantsListScreen(),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Row(
                      children: [
                        Text(
                          'Show All',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                key: ValueKey(_retryToken),
                stream: FirestoreService.activeRestaurants(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return SizedBox(
                      height: 120,
                      child: AsyncStateMessage(
                        icon: Icons.error_outline_rounded,
                        message: 'Failed to load restaurants',
                        actionLabel: 'Retry',
                        onAction: _retry,
                      ),
                    );
                  }

                  final restaurants = (snapshot.data?.docs ?? [])
                      .map(Restaurant.fromDoc)
                      .where((r) => r.name.isNotEmpty)
                      .where(diet.matchesRestaurant)
                      .where(filters.matchesRestaurant)
                      .take(widget.maxItems)
                      .toList();

                  if (restaurants.isEmpty) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: Text('No restaurants available')),
                    );
                  }

                  // Build rows manually so the layout takes exactly the
                  // space the cards need — no empty last-row gap.
                  final rows = <Widget>[];
                  for (var i = 0; i < restaurants.length; i += 2) {
                    final left = restaurants[i];
                    final right = i + 1 < restaurants.length
                        ? restaurants[i + 1]
                        : null;
                    rows.add(
                      Row(
                        children: [
                          Expanded(child: RestaurantCard(restaurant: left)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: right != null
                                ? RestaurantCard(restaurant: right)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    );
                    if (i + 2 < restaurants.length) {
                      rows.add(const SizedBox(height: 10));
                    }
                  }
                  return Column(children: rows);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppNavigation.push(
          context,
          RestaurantMenuScreen(restaurant: restaurant),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  restaurant.imageUrl.isNotEmpty
                      ? Image.network(
                          restaurant.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Color(0xFFFFD700),
                          ),
                          const SizedBox(width: 2),
                          // rating is now averageRating (dynamic); falls back
                          // to the static seed value when no reviews exist yet.
                          Text(
                            restaurant.rating > 0
                                ? restaurant.rating.toStringAsFixed(1)
                                : 'New',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (restaurant.totalReviews > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              '(${restaurant.totalReviews})',
                              style: const TextStyle(
                                color: Color(0xFFFFEBEB),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: FavoriteRestaurantButton(
                      restaurant: restaurant,
                      size: 30,
                      iconSize: 16,
                    ),
                  ),
                  if (restaurant.isVeg)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Pure Veg',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    restaurant.cuisine.isEmpty
                        ? restaurant.locationLabel
                        : restaurant.cuisine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: Color(0xFF6B6B6B),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          restaurant.deliveryTime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B6B6B),
                          ),
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
      color: const Color(0xFFFFE8E8),
      child: const Center(
        child: Icon(
          Icons.storefront_rounded,
          color: AppColors.primary,
          size: 40,
        ),
      ),
    );
  }
}
