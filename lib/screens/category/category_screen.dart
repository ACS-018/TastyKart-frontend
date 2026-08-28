import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/color_constants.dart';
import '../../models/food_item.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../restaurant/restaurant_menu_screen.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.categoryName});

  final String categoryName;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String? _selectedSub;
  String? _filter; // veg | nonveg | top | kids

  static const _biryaniSubs = [
    _SubCat('Chicken Biryani',
        'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=200'),
    _SubCat('Mutton Biryani',
        'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=200'),
    _SubCat('Egg Biryani',
        'https://images.unsplash.com/photo-1631515243349-e0cb75fb8d3a?w=200'),
    _SubCat('Beef Biryani',
        'https://images.unsplash.com/photo-1599043513900-ed6fe01d3833?w=200'),
    _SubCat('Veg Biryani',
        'https://images.unsplash.com/photo-1642821373181-696a54913e93?w=200'),
  ];

  List<_SubCat> get _subs {
    if (widget.categoryName.toLowerCase().contains('biryani')) {
      return _biryaniSubs;
    }
    return [
      _SubCat(widget.categoryName,
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=200'),
    ];
  }

  bool _matchesCuisine(Restaurant r) {
    final cat = widget.categoryName.toLowerCase();
    return r.cuisine.toLowerCase().contains(cat) ||
        r.name.toLowerCase().contains(cat);
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirestoreService.activeRestaurants(),
              builder: (context, restSnap) {
                if (restSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var restaurants = (restSnap.data?.docs ?? [])
                    .map(Restaurant.fromDoc)
                    .where((r) => r.name.isNotEmpty)
                    .where(_matchesCuisine)
                    .toList();

                // If no cuisine match, show all active restaurants
                if (restaurants.isEmpty) {
                  restaurants = (restSnap.data?.docs ?? [])
                      .map(Restaurant.fromDoc)
                      .where((r) => r.name.isNotEmpty)
                      .toList();
                }

                if (_filter == 'veg') {
                  restaurants = restaurants.where((r) => r.isVeg).toList();
                } else if (_filter == 'top') {
                  restaurants =
                      restaurants.where((r) => r.rating >= 4.0).toList();
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirestoreService.activeFoodItems(),
                  builder: (context, foodSnap) {
                    final foods = (foodSnap.data?.docs ?? [])
                        .map(FoodItem.fromDoc)
                        .where((f) => f.name.isNotEmpty)
                        .toList();

                    // Legacy fallback: derive restaurants from foodItems
                    if (restaurants.isEmpty && foods.isNotEmpty) {
                      final catLower = widget.categoryName.toLowerCase();
                      final filtered = foods.where((f) {
                        return f.categoryName.toLowerCase().contains(catLower) ||
                            f.name.toLowerCase().contains(catLower) ||
                            f.tags.any(
                                (t) => t.toLowerCase().contains(catLower));
                      }).toList();
                      final byName = <String, List<FoodItem>>{};
                      for (final f
                          in (filtered.isNotEmpty ? filtered : foods)) {
                        byName.putIfAbsent(f.restaurantName, () => []).add(f);
                      }
                      return _buildListFromFoodGroups(byName.entries.toList());
                    }

                    return _buildListFromRestaurants(restaurants, foods);
                  },
                );
              },
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
      final match = foods.where((f) =>
          f.restaurantId == r.id ||
          f.restaurantName.toLowerCase() == r.name.toLowerCase());
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
        const SizedBox(height: 16),
        _subCatsRow(),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Top Restaurant',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Restaurant Special Offers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
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
        const SizedBox(height: 16),
        _subCatsRow(),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Top Restaurant',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Restaurant Special Offers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
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

  Widget _subCatsRow() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _subs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final s = _subs[i];
          final selected = _selectedSub == s.name;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedSub = selected ? null : s.name;
            }),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          selected ? AppColors.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.network(
                      s.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFEEEEEE),
                        child: const Icon(Icons.restaurant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 72,
                  child: Text(
                    s.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 16,
        bottom: 18,
      ),
      color: AppColors.primary,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Your Recipes Listings',
                style: TextStyle(color: AppColors.white, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOn ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOn ? AppColors.primary : const Color(0xFFDDDDDD),
                ),
              ),
              child: Row(
                children: [
                  if (isDot)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOn ? AppColors.white : color,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: isOn ? AppColors.white : color,
                      ),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOn ? AppColors.white : const Color(0xFF333333),
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

class _TopRestaurantCard extends StatefulWidget {
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
  State<_TopRestaurantCard> createState() => _TopRestaurantCardState();
}

class _TopRestaurantCardState extends State<_TopRestaurantCard> {
  bool _fav = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    final s = widget.sample;
    final name = r?.name ?? widget.restaurantName ?? '';
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
      onTap: widget.onTap,
      child: Container(
        width: 160,
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
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _fav = !_fav),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.white.withOpacity(0.9),
                        child: Icon(
                          _fav ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Icon(Icons.star_rounded,
                              size: 12, color: AppColors.white),
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
    final priceLabel = s != null ? '₹${s.displayPrice}' : (r != null && r.minOrder > 0
        ? 'Min ₹${r.minOrder}'
        : '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
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
                            horizontal: 6, vertical: 3),
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
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: Color(0xFFFFB300)),
                      Text(
                        ' ${rating.toStringAsFixed(1)}',
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

class _SubCat {
  final String name;
  final String imageUrl;
  const _SubCat(this.name, this.imageUrl);
}
