import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../state/diet_filter_controller.dart';
import '../../utils/app_navigation.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/async_state_message.dart';
import '../restaurant/restaurant_menu_screen.dart';

/// Full restaurant list with category filters
class AllRestaurantsListScreen extends StatefulWidget {
  const AllRestaurantsListScreen({super.key});

  @override
  State<AllRestaurantsListScreen> createState() =>
      _AllRestaurantsListScreenState();
}

class _AllRestaurantsListScreenState extends State<AllRestaurantsListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedCategory = 'all';
  List<Map<String, dynamic>> _categories = [];
  int _retryToken = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _retry() => setState(() => _retryToken++);

  @override
  Widget build(BuildContext context) {
    final diet = DietFilterScope.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'All Restaurants',
            subtitle: 'Browse all available restaurants',
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

          // ── Category filter chips ───────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirestoreService.activeRestaurantCategories(),
            builder: (context, categorySnap) {
              if (categorySnap.hasData) {
                _categories = (categorySnap.data?.docs ?? [])
                    .map((doc) => doc.data() as Map<String, dynamic>)
                    .where((cat) => cat['name'] != null)
                    .toList();
              }

              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _CategoryChip(
                      label: 'All',
                      isSelected: _selectedCategory == 'all',
                      onTap: () => setState(() => _selectedCategory = 'all'),
                    ),
                    ..._categories.map((cat) {
                      final id = cat['id'] ?? '';
                      final name = cat['name'] ?? 'Unknown';
                      return _CategoryChip(
                        label: name,
                        isSelected: _selectedCategory == id,
                        onTap: () => setState(() => _selectedCategory = id),
                      );
                    }),
                  ],
                ),
              );
            },
          ),

          // ── Restaurant list ─────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              key: ValueKey(_retryToken),
              stream: FirestoreService.activeRestaurants(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return AsyncStateMessage(
                    icon: Icons.error_outline_rounded,
                    message: 'Failed to load restaurants',
                    actionLabel: 'Retry',
                    onAction: _retry,
                  );
                }

                var restaurants = (snapshot.data?.docs ?? [])
                    .map(Restaurant.fromDoc)
                    .where((r) => r.name.isNotEmpty)
                    .where(diet.matchesRestaurant)
                    .toList();

                // Apply search filter
                if (_query.isNotEmpty) {
                  final q = _query.toLowerCase();
                  restaurants = restaurants
                      .where((r) =>
                          r.name.toLowerCase().contains(q) ||
                          r.cuisine.toLowerCase().contains(q))
                      .toList();
                }

                // Apply category filter
                if (_selectedCategory != 'all') {
                  restaurants = restaurants
                      .where((r) => r.categories.contains(_selectedCategory))
                      .toList();
                }

                if (restaurants.isEmpty) {
                  return const Center(
                    child: Text(
                      'No restaurants found',
                      style: TextStyle(color: Color(0xFF6B6B6B)),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Count
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${restaurants.length} restaurant${restaurants.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B6B6B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    // List
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: restaurants.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final r = restaurants[i];
                          return _RestaurantListCard(
                            restaurant: r,
                            onTap: () => AppNavigation.push(
                              context,
                              RestaurantMenuScreen(restaurant: r),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.primary : const Color(0xFFEEEEEE),
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSelected ? AppColors.white : const Color(0xFF6B6B6B),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestaurantListCard extends StatelessWidget {
  const _RestaurantListCard({
    required this.restaurant,
    required this.onTap,
  });

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 140,
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
                    // Rating badge
                    Positioned(
                      top: 10,
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
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Color(0xFFFFD700),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              restaurant.rating > 0
                                  ? restaurant.rating.toStringAsFixed(1)
                                  : 'New',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Details
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (restaurant.isVeg)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green, width: 1.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    restaurant.cuisine,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),
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
                        restaurant.deliveryTime,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B6B6B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.restaurant_menu_rounded,
                        size: 14,
                        color: Color(0xFF6B6B6B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '₹${restaurant.minOrder} min',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B6B6B),
                          fontWeight: FontWeight.w600,
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
      child: const Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 40,
          color: Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}
