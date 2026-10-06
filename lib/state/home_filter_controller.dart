import 'package:flutter/material.dart';

import '../models/food_item.dart';
import '../models/restaurant.dart';

/// Home chip + cuisine filters (separate from veg/non-veg diet mode).
enum HomeChipFilter { none, newToYou, offers, ratings4Plus }

class HomeFilterController extends ChangeNotifier {
  HomeChipFilter _chip = HomeChipFilter.none;
  Set<String> _cuisines = {};

  HomeChipFilter get chip => _chip;
  Set<String> get cuisines => Set.unmodifiable(_cuisines);

  bool get hasActiveFilters =>
      _chip != HomeChipFilter.none || _cuisines.isNotEmpty;

  void setChip(HomeChipFilter value) {
    if (_chip == value) return;
    _chip = value;
    notifyListeners();
  }

  void toggleChip(HomeChipFilter value) {
    _chip = _chip == value ? HomeChipFilter.none : value;
    notifyListeners();
  }

  void setCuisines(Set<String> value) {
    _cuisines = Set<String>.from(value);
    notifyListeners();
  }

  void clear() {
    _chip = HomeChipFilter.none;
    _cuisines = {};
    notifyListeners();
  }

  bool matchesRestaurant(Restaurant restaurant) {
    if (_cuisines.isNotEmpty) {
      // Primary: check admin-assigned category IDs (same logic as Explore /
      // CategoryScreen). _cuisines now holds Firestore doc IDs returned by
      // CuisineFilterSheet.
      final hasIdMatch = _cuisines.any(
        (id) => restaurant.categories.contains(id),
      );
      // Fallback: free-text match on cuisine / name for restaurants that were
      // seeded before the categories array was introduced.
      final cuisine = restaurant.cuisine.toLowerCase();
      final hasFallbackMatch = _cuisines.any(
        (id) =>
            cuisine.contains(id.toLowerCase()) ||
            restaurant.name.toLowerCase().contains(id.toLowerCase()),
      );
      if (!hasIdMatch && !hasFallbackMatch) return false;
    }

    switch (_chip) {
      case HomeChipFilter.none:
        return true;
      case HomeChipFilter.newToYou:
        // Proxy for "new" when Admin has no isNew flag.
        return restaurant.totalOrders < 40 || restaurant.featured;
      case HomeChipFilter.offers:
        return restaurant.featured || restaurant.minOrder > 0;
      case HomeChipFilter.ratings4Plus:
        return restaurant.rating >= 4.0;
    }
  }

  bool matchesFood(FoodItem item) {
    if (_cuisines.isNotEmpty) {
      final hay = '${item.categoryName} ${item.tags.join(' ')} ${item.name}'
          .toLowerCase();
      final hit = _cuisines.any((c) => hay.contains(c.toLowerCase()));
      if (!hit) return false;
    }

    switch (_chip) {
      case HomeChipFilter.none:
        return true;
      case HomeChipFilter.newToYou:
        return item.tags.any((t) => t.toLowerCase().contains('new')) ||
            item.totalRatings < 15;
      case HomeChipFilter.offers:
        return item.hasDiscount;
      case HomeChipFilter.ratings4Plus:
        return item.rating >= 4.0;
    }
  }
}

class HomeFilterScope extends InheritedNotifier<HomeFilterController> {
  const HomeFilterScope({
    super.key,
    required HomeFilterController controller,
    required super.child,
  }) : super(notifier: controller);

  static HomeFilterController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HomeFilterScope>();
    assert(scope != null, 'HomeFilterScope not found in widget tree');
    return scope!.notifier!;
  }

  static HomeFilterController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<HomeFilterScope>()
        ?.notifier;
  }
}
