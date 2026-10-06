import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../models/food_item.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/favorite_restaurant_button.dart';
import '../restaurant/restaurant_menu_screen.dart';

class AllRestaurantsScreen extends StatefulWidget {
  const AllRestaurantsScreen({
    super.key,
    required this.categoryName,
    required this.restaurants,
  });

  final String categoryName;
  final List<Restaurant> restaurants;

  static Future<void> open(
    BuildContext context, {
    required String categoryName,
    required List<Restaurant> restaurants,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AllRestaurantsScreen(
          categoryName: categoryName,
          restaurants: restaurants,
        ),
      ),
    );
  }

  @override
  State<AllRestaurantsScreen> createState() => _AllRestaurantsScreenState();
}

class _AllRestaurantsScreenState extends State<AllRestaurantsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.restaurants.where((r) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return r.name.toLowerCase().contains(q) ||
          r.cuisine.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Column(
        children: [
          AppScreenHeader(
            title: widget.categoryName,
            subtitle: 'All restaurants',
            onBack: () => Navigator.pop(context),
          ),

          // ── Search bar ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search restaurants...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9E9E9E),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF9E9E9E),
                  size: 20,
                ),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF9E9E9E),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // ── Count ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} restaurant${filtered.length != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
              ),
            ),
          ),

          // ── List ────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No restaurants found',
                      style: TextStyle(color: Color(0xFF6B6B6B)),
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirestoreService.activeFoodItems(),
                    builder: (context, foodSnap) {
                      final foods = (foodSnap.data?.docs ?? [])
                          .map(FoodItem.fromDoc)
                          .where((f) => f.name.isNotEmpty)
                          .toList();

                      FoodItem? sampleFor(Restaurant r) {
                        try {
                          return foods.firstWhere(
                            (f) =>
                                f.restaurantId == r.id ||
                                f.restaurantName.toLowerCase() ==
                                    r.name.toLowerCase(),
                          );
                        } catch (_) {
                          return null;
                        }
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final s = sampleFor(r);
                          return _RestaurantOfferCard(
                            restaurant: r,
                            sample: s,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RestaurantMenuScreen(restaurant: r),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantOfferCard extends StatelessWidget {
  const _RestaurantOfferCard({
    required this.restaurant,
    this.sample,
    required this.onTap,
  });

  final Restaurant restaurant;
  final FoodItem? sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final s = sample;
    final image = r.imageUrl.isNotEmpty ? r.imageUrl : (s?.image ?? '');
    final subtitle =
        '${r.deliveryTime} · ${r.cuisine.isEmpty ? 'Restaurant' : r.cuisine}';
    final desc = r.description ?? '';
    final rating = r.rating;
    final priceLabel = r.minOrder > 0 ? 'Min ₹${r.minOrder}' : '';
    final locationLabel = r.locationLabel;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Thumbnail with favourite button ─────────────────
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: image.isEmpty
                        ? Container(color: const Color(0xFFEEEEEE))
                        : Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFFEEEEEE)),
                          ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: FavoriteRestaurantButton(
                      restaurant: r,
                      size: 26,
                      iconSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ── Info ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                  ],
                  if (locationLabel.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      locationLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFFFB300),
                      ),
                      Text(
                        ' ${rating > 0 ? rating.toStringAsFixed(1) : 'New'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (priceLabel.isNotEmpty)
                        Text(
                          priceLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
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
