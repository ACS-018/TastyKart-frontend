import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/color_constants.dart';
import '../../models/food_item.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/favorite_restaurant_button.dart';
import '../restaurant/restaurant_menu_screen.dart';
import 'all_restaurants_screen.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.categoryName,
    this.categoryId,
  });

  final String categoryName;

  /// Firestore doc ID from `restaurantCategories`.
  /// When provided, a restaurant is included if its `categories` array
  /// contains this ID — the admin-configured assignment takes priority
  /// over the cuisine-text heuristic.
  final String? categoryId;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String? _filter; // veg | nonveg | top | kids

  /// Returns true when this restaurant belongs to the selected category.
  ///
  /// Priority order:
  ///   1. Admin-assigned: `r.categories` contains the category's Firestore doc ID.
  ///      When a categoryId is provided we trust ONLY this — the text heuristic
  ///      is skipped so unrelated restaurants never appear.
  ///   2. Text heuristic: only used as a fallback when NO categoryId was
  ///      provided (e.g. navigated from a deep-link with name only).
  bool _matchesCuisine(Restaurant r) {
    // ── 1. Admin assignment (exact ID match) ────────────────────────────────
    final catId = widget.categoryId;
    if (catId != null && catId.isNotEmpty) {
      // Strict: only show restaurants explicitly assigned by the admin.
      return r.categories.contains(catId);
    }

    // ── 2. Text heuristic — only when no categoryId was provided ─────────────
    final catRaw = widget.categoryName.toLowerCase().trim();
    final cuisineLow = r.cuisine.toLowerCase();
    final nameLow = r.name.toLowerCase();

    // Strip trailing digits so "North Indian1" → "north indian"
    final catClean = catRaw.replaceAll(RegExp(r'\d+$'), '').trim();

    if (cuisineLow.contains(catClean) || nameLow.contains(catClean)) {
      return true;
    }
    if (catClean.contains(cuisineLow) && cuisineLow.isNotEmpty) return true;

    // Token-based: split on non-word chars, match any meaningful token
    // Use length >= 4 to reduce false positives (avoids "ica", "chi" etc.)
    final catTokens = catClean
        .split(RegExp(r'[\s,\-_]+'))
        .where((t) => t.length >= 4)
        .toList();
    for (final token in catTokens) {
      if (cuisineLow.contains(token) || nameLow.contains(token)) return true;
    }

    // Check cuisine tokens against category name
    final cuisineTokens = cuisineLow
        .split(RegExp(r'[\s,\-_]+'))
        .where((t) => t.length >= 4)
        .toList();
    for (final token in cuisineTokens) {
      if (catClean.contains(token)) return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Column(
        children: [
          _Header(title: widget.categoryName),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF9F9F9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirestoreService.activeRestaurants(),
                builder: (context, restSnap) {
                  if (restSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allActive = (restSnap.data?.docs ?? [])
                      .map(Restaurant.fromDoc)
                      .where((r) => r.name.isNotEmpty)
                      .toList();

                  // Filter to this cuisine / category first.
                  var restaurants = allActive.where(_matchesCuisine).toList();

                  // Only fall back to all active restaurants when there is no
                  // category-ID set AND nothing matched the text heuristic.
                  // When a categoryId is provided, we never fall back to all
                  // restaurants — an empty result means the admin hasn't
                  // assigned any restaurants to this category yet.
                  if (restaurants.isEmpty &&
                      allActive.isNotEmpty &&
                      (widget.categoryId == null ||
                          widget.categoryId!.isEmpty)) {
                    restaurants = allActive;
                  }

                  // Apply diet filters
                  if (_filter == 'veg') {
                    restaurants = restaurants.where((r) => r.isVeg).toList();
                  } else if (_filter == 'nonveg') {
                    restaurants = restaurants.where((r) => !r.isVeg).toList();
                  } else if (_filter == 'top') {
                    restaurants = restaurants
                        .where((r) => r.rating >= 4.0)
                        .toList();
                  }
                  // 'kids' filter has no backend field — show all when selected.

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirestoreService.activeFoodItems(),
                    builder: (context, foodSnap) {
                      final foods = (foodSnap.data?.docs ?? [])
                          .map(FoodItem.fromDoc)
                          .where((f) => f.name.isNotEmpty)
                          .toList();

                      // Legacy fallback: derive restaurants from foodItems.
                      // Only used when NO categoryId is set — if a categoryId
                      // is provided and no restaurants matched, the admin
                      // simply hasn't assigned any yet; show empty, not all.
                      if (restaurants.isEmpty &&
                          foods.isNotEmpty &&
                          (widget.categoryId == null ||
                              widget.categoryId!.isEmpty)) {
                        final catLow = widget.categoryName
                            .toLowerCase()
                            .replaceAll(RegExp(r'\d+$'), '')
                            .trim();
                        final filtered = foods.where((f) {
                          return f.categoryName.toLowerCase().contains(
                                catLow,
                              ) ||
                              f.name.toLowerCase().contains(catLow) ||
                              f.tags.any(
                                (t) => t.toLowerCase().contains(catLow),
                              );
                        }).toList();
                        final byName = <String, List<FoodItem>>{};
                        for (final f
                            in (filtered.isNotEmpty ? filtered : foods)) {
                          byName.putIfAbsent(f.restaurantName, () => []).add(f);
                        }
                        return _buildListFromFoodGroups(
                          byName.entries.toList(),
                        );
                      }

                      return _buildListFromRestaurants(restaurants, foods);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListFromRestaurants(
    List<Restaurant> restaurants,
    List<FoodItem> foods,
  ) {
    FoodItem? sampleFor(Restaurant r) {
      final match = foods.where(
        (f) =>
            f.restaurantId == r.id ||
            f.restaurantName.toLowerCase() == r.name.toLowerCase(),
      );
      return match.isEmpty ? null : match.first;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        _DietFilters(
          selected: _filter,
          onChanged: (v) => setState(() => _filter = _filter == v ? null : v),
        ),
        const SizedBox(height: 8),

        // ── Top Restaurant header ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Restaurant',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () => AllRestaurantsScreen.open(
                  context,
                  categoryName: widget.categoryName,
                  restaurants: restaurants,
                ),
                child: const Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: 210,
          child: restaurants.isEmpty
              ? const Center(child: Text('No restaurants found'))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: restaurants.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final r = restaurants[i];
                    return _TopRestaurantCard(
                      restaurant: r,
                      sample: sampleFor(r),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantMenuScreen(restaurant: r),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // ── Restaurant Special Offers header ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Restaurant Special Offers',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () => AllRestaurantsScreen.open(
                  context,
                  categoryName: widget.categoryName,
                  restaurants: restaurants,
                ),
                child: const Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        ...restaurants.map((r) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _OfferRowCard(
              restaurant: r,
              sample: sampleFor(r),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RestaurantMenuScreen(restaurant: r),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildListFromFoodGroups(
    List<MapEntry<String, List<FoodItem>>> groups,
  ) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        _DietFilters(
          selected: _filter,
          onChanged: (v) => setState(() => _filter = _filter == v ? null : v),
        ),
        const SizedBox(height: 8),

        // ── Top Restaurant header ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Restaurant',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () => AllRestaurantsScreen.open(
                  context,
                  categoryName: widget.categoryName,
                  restaurants: const [],
                ),
                child: const Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: 210,
          child: groups.isEmpty
              ? const Center(child: Text('No restaurants found'))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final entry = groups[i];
                    final top = entry.value.first;
                    return _TopRestaurantCard(
                      restaurantName: entry.key,
                      sample: top,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantMenuScreen(
                            restaurantId: top.restaurantId,
                            restaurantName: entry.key,
                            highlightItem: top,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // ── Restaurant Special Offers header ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Restaurant Special Offers',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () => AllRestaurantsScreen.open(
                  context,
                  categoryName: widget.categoryName,
                  restaurants: const [],
                ),
                child: const Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        ...groups.map((e) {
          final sample = e.value.first;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _OfferRowCard(
              restaurantName: e.key,
              sample: sample,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RestaurantMenuScreen(
                    restaurantId: sample.restaurantId,
                    restaurantName: e.key,
                    highlightItem: sample,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AppScreenHeader(
      title: title,
      subtitle: 'Explore your favourite cuisines',
      onBack: () => Navigator.pop(context),
    );
  }
}

// ── Diet filter chips ───────────────────────────────────────────────────────

class _DietFilters extends StatelessWidget {
  const _DietFilters({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('veg', 'Veg', const Color(0xFF2E7D32), true),
      ('nonveg', 'Non Veg', const Color(0xFFB71C1C), true),
      ('top', 'Top Rated', const Color(0xFFFFB300), false),
      ('kids', 'Kids Friendly', AppColors.primary, false),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = chips[i].$1;
          final label = chips[i].$2;
          final color = chips[i].$3;
          final isDot = chips[i].$4;
          final isOn = selected == id;
          return GestureDetector(
            onTap: () => onChanged(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOn ? AppColors.primary : const Color(0xFFDDDDDD),
                  width: isOn ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDot)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.star_rounded, size: 14, color: color),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOn ? AppColors.primary : const Color(0xFF333333),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Top Restaurant card ─────────────────────────────────────────────────────

class _TopRestaurantCard extends StatelessWidget {
  const _TopRestaurantCard({
    this.restaurant,
    this.restaurantName,
    this.sample,
    required this.onTap,
  });

  final Restaurant? restaurant;
  final String? restaurantName;
  final FoodItem? sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final s = sample;
    final name = r?.name ?? restaurantName ?? '';
    final image = (r?.imageUrl.isNotEmpty == true)
        ? r!.imageUrl
        : (s?.image ?? '');
    final rating = r?.rating ?? s?.rating ?? 0;
    final time = r?.deliveryTime.isNotEmpty == true
        ? r!.deliveryTime
        : (s != null
              ? '${s.preparationTime}-${s.preparationTime + 10} Min'
              : '30-40 Min');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
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
              height: 130,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image.isEmpty
                      ? Container(color: const Color(0xFFEEEEEE))
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: const Color(0xFFEEEEEE)),
                        ),

                  // ── Favourite button (Firestore-backed) ─────────
                  Positioned(
                    top: 8,
                    right: 8,
                    child: r != null
                        ? FavoriteRestaurantButton(
                            restaurant: r,
                            size: 30,
                            iconSize: 16,
                          )
                        : const SizedBox.shrink(),
                  ),

                  // ── Rating badge ────────────────────────────────
                  Positioned(
                    bottom: 8,
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
                          Text(
                            rating > 0 ? rating.toStringAsFixed(1) : 'New',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B6B6B),
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

// ── Offer row card ──────────────────────────────────────────────────────────

class _OfferRowCard extends StatelessWidget {
  const _OfferRowCard({
    this.restaurant,
    this.restaurantName,
    this.sample,
    required this.onTap,
  });

  final Restaurant? restaurant;
  final String? restaurantName;
  final FoodItem? sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final s = sample;
    final name = r?.name ?? restaurantName ?? '';
    final image = (r?.imageUrl.isNotEmpty == true)
        ? r!.imageUrl
        : (s?.image ?? '');
    final subtitle = r != null
        ? '${r.deliveryTime} · ${r.cuisine.isEmpty ? 'Restaurant' : r.cuisine}'
        : (s != null
              ? '${s.preparationTime} Min · ${s.categoryName.isEmpty ? s.name : s.categoryName}'
              : '');
    final desc = r?.description ?? s?.description ?? '';
    final rating = r?.rating ?? s?.rating ?? 0;
    final priceLabel = s != null
        ? '₹${s.displayPrice}'
        : (r != null && r.minOrder > 0 ? 'Min ₹${r.minOrder}' : '');
    final locationLabel = r?.locationLabel ?? '';

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
            // ── Thumbnail with discount badge + fav button ────────
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
                  if (s?.hasDiscount == true)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          '${s!.discountPercent}% Off',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  // ── Favourite button — top-right of image ───────
                  if (r != null)
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

            // ── Restaurant info ───────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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
