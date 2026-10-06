import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/color_constants.dart';
import '../../models/favorite_restaurant.dart';
import '../../state/favorites_controller.dart';
import '../../utils/app_navigation.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/async_state_message.dart';
import '../../widgets/favorite_restaurant_button.dart';
import '../restaurant/restaurant_menu_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _refreshToken = 0;

  Future<void> _onRefresh() async {
    setState(() => _refreshToken++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final favorites = FavoritesScope.maybeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Favorites',
            subtitle: 'Your favourite restaurants',
            onBack: widget.embedded ? null : () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: uid == null
                  ? const Center(
                      child: Text(
                        'Sign in to view your favourite restaurants.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6B6B6B)),
                      ),
                    )
                  : favorites == null
                  ? const AsyncStateMessage.loading()
                  : ListenableBuilder(
                      key: ValueKey(_refreshToken),
                      listenable: favorites,
                      builder: (context, _) {
                        final items = favorites.favorites;

                        if (items.isEmpty) {
                          return RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _onRefresh,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                AsyncStateMessage(
                                  icon: Icons.favorite_border_rounded,
                                  message:
                                      'No favourite restaurants yet.\nTap the heart on a restaurant to save it.',
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _onRefresh,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              widget.embedded ? 100 : 24,
                            ),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              return _FavoriteRestaurantCard(
                                favorite: items[index],
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteRestaurantCard extends StatelessWidget {
  const _FavoriteRestaurantCard({required this.favorite});

  final FavoriteRestaurant favorite;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppNavigation.push(
          context,
          RestaurantMenuScreen(
            restaurantId: favorite.restaurantId,
            restaurantName: favorite.restaurantName,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
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
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  favorite.imageUrl.isNotEmpty
                      ? Image.network(
                          favorite.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: const Color(0xFFEEEEEE)),
                        )
                      : Container(
                          color: const Color(0xFFFFE8E8),
                          child: const Center(
                            child: Icon(
                              Icons.storefront_rounded,
                              color: AppColors.primary,
                              size: 48,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: FavoriteRestaurantButton(
                      restaurant: favorite.toRestaurant(),
                    ),
                  ),
                  if (favorite.rating > 0)
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
                          children: [
                            Text(
                              favorite.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
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
                    favorite.restaurantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (favorite.cuisine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      favorite.cuisine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                  ],
                  if (favorite.deliveryTime.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Color(0xFF6B6B6B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          favorite.deliveryTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
