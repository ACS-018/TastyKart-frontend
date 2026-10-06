import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/color_constants.dart';
import '../../global_widgets/app_back_button.dart';
import '../../models/food_item.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../services/search_service.dart';
import '../../state/diet_filter_controller.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_navigation.dart';
import '../restaurant/restaurant_menu_screen.dart';

/// Global search — restaurants and dishes from Firestore.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, this.dietMode = DietMode.nonVeg});

  final DietMode dietMode;

  static Future<void> open(
    BuildContext context, {
    DietMode dietMode = DietMode.nonVeg,
  }) {
    return AppNavigation.push(context, GlobalSearchScreen(dietMode: dietMode));
  }

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Restaurant> _restaurants = const [];
  List<FoodItem> _foodItems = const [];
  bool _catalogLoading = true;
  late DietMode _dietMode;

  StreamSubscription<QuerySnapshot>? _restaurantsSub;
  StreamSubscription<QuerySnapshot>? _foodSub;

  @override
  void initState() {
    super.initState();
    _dietMode = widget.dietMode;
    _bindCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _bindCatalog() {
    _restaurantsSub?.cancel();
    _foodSub?.cancel();

    _restaurantsSub = FirestoreService.activeRestaurants().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _restaurants = snap.docs
              .map(Restaurant.fromDoc)
              .where((r) => r.name.isNotEmpty)
              .toList();
          _catalogLoading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _catalogLoading = false);
      },
    );

    _foodSub = FirestoreService.activeFoodItems(availableOnly: true).listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _foodItems = snap.docs
              .map(FoodItem.fromDoc)
              .where((f) => f.name.isNotEmpty)
              .toList();
          _catalogLoading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _catalogLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _restaurantsSub?.cancel();
    _foodSub?.cancel();
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  GlobalSearchResults get _results => SearchService.search(
    restaurants: _restaurants,
    foodItems: _foodItems,
    query: _queryController.text,
    dietMode: _dietMode,
  );

  void _toggleDietMode() {
    setState(() {
      _dietMode = _dietMode == DietMode.veg ? DietMode.nonVeg : DietMode.veg;
    });
    DietFilterScope.maybeOf(context)?.setVegMode(_dietMode == DietMode.veg);
    AppFeedback.selection();
  }

  void _openRestaurant(Restaurant restaurant) {
    AppNavigation.push(context, RestaurantMenuScreen(restaurant: restaurant));
  }

  void _openFoodItem(FoodItem item) {
    AppNavigation.push(
      context,
      RestaurantMenuScreen(
        restaurantId: item.restaurantId,
        restaurantName: item.restaurantName,
        highlightItem: item,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim();
    final results = _results;
    final hasQuery = query.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: const AppBackButton(),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _queryController,
            focusNode: _focusNode,
            autofocus: true,
            style: const TextStyle(color: AppColors.white, fontSize: 16),
            cursorColor: AppColors.white,
            decoration: InputDecoration(
              hintText: 'Search food or kitchens',
              hintStyle: TextStyle(
                color: AppColors.white.withValues(alpha: 0.75),
                fontSize: 15,
              ),
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: AppColors.white.withValues(alpha: 0.9),
              ),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _queryController.clear();
                        setState(() {});
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.white.withValues(alpha: 0.9),
                      ),
                    )
                  : null,
            ),
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _dietMode == DietMode.veg ? 'Veg only' : 'All items',
            onPressed: _toggleDietMode,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: _dietMode == DietMode.veg
                  // Veg: green-bordered square with a green filled circle
                  ? Container(
                      key: const ValueKey('veg'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF2E7D32),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          radius: 5,
                          backgroundColor: Color(0xFF2E7D32),
                        ),
                      ),
                    )
                  // Non-veg: red-bordered square with a red filled triangle
                  : Container(
                      key: const ValueKey('nonveg'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFB71C1C),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: CustomPaint(
                          size: const Size(9, 9),
                          painter: _TrianglePainter(
                            color: const Color(0xFFB71C1C),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F5F5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: _catalogLoading
            ? const Center(child: CircularProgressIndicator())
            : !hasQuery
            ? _EmptyPrompt(
                restaurants: _restaurants,
                onRestaurantTap: _openRestaurant,
              )
            : results.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 56,
                        color: AppColors.textLight.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No results for "$query"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Try another dish or restaurant name',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (results.restaurants.isNotEmpty) ...[
                    const _SectionTitle(
                      icon: Icons.storefront_rounded,
                      label: 'Restaurants',
                    ),
                    const SizedBox(height: 10),
                    ...results.restaurants.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RestaurantResultTile(
                          restaurant: r,
                          onTap: () => _openRestaurant(r),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (results.foodItems.isNotEmpty) ...[
                    const _SectionTitle(
                      icon: Icons.restaurant_menu_rounded,
                      label: 'Dishes',
                    ),
                    const SizedBox(height: 10),
                    ...results.foodItems.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FoodResultTile(
                          item: f,
                          onTap: () => _openFoodItem(f),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({
    required this.restaurants,
    required this.onRestaurantTap,
  });

  final List<Restaurant> restaurants;
  final ValueChanged<Restaurant> onRestaurantTap;

  @override
  Widget build(BuildContext context) {
    final picks = restaurants.where((r) => r.popular).take(6).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.search_rounded,
          size: 48,
          color: AppColors.textLight.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 12),
        const Text(
          'Search for food or kitchens',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Find restaurants by name or cuisine, or search dishes across all kitchens.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textMedium,
          ),
        ),
        if (picks.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text(
            'Popular restaurants',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          ...picks.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RestaurantResultTile(
                restaurant: r,
                onTap: () => onRestaurantTap(r),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _RestaurantResultTile extends StatelessWidget {
  const _RestaurantResultTile({required this.restaurant, required this.onTap});

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _ThumbImage(
                url: restaurant.imageUrl,
                icon: Icons.storefront_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (restaurant.cuisine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        restaurant.cuisine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMedium,
                        ),
                      ),
                    ],
                    if (restaurant.deliveryTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        restaurant.deliveryTime,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (restaurant.rating > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        restaurant.rating.toStringAsFixed(1),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodResultTile extends StatelessWidget {
  const _FoodResultTile({required this.item, required this.onTap});

  final FoodItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _ThumbImage(url: item.image, icon: Icons.restaurant_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.restaurantName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.restaurantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMedium,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '₹${item.displayPrice}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.isVeg)
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF2E7D32),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbImage extends StatelessWidget {
  const _ThumbImage({required this.url, required this.icon});

  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(icon),
              )
            : _placeholder(icon),
      ),
    );
  }

  Widget _placeholder(IconData icon) {
    return Container(
      color: const Color(0xFFFFE8E8),
      child: Center(child: Icon(icon, color: AppColors.primary, size: 26)),
    );
  }
}

/// Paints a solid upward-pointing triangle — standard non-veg indicator.
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0) // top-center
      ..lineTo(size.width, size.height) // bottom-right
      ..lineTo(0, size.height) // bottom-left
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
