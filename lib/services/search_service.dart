import '../models/food_item.dart';
import '../models/restaurant.dart';
import '../state/diet_filter_controller.dart';

/// Client-side search over active restaurants and food items from Firestore.
class GlobalSearchResults {
  const GlobalSearchResults({
    required this.restaurants,
    required this.foodItems,
  });

  final List<Restaurant> restaurants;
  final List<FoodItem> foodItems;

  bool get isEmpty => restaurants.isEmpty && foodItems.isEmpty;
}

class SearchService {
  SearchService._();

  static bool _contains(String value, String query) {
    return value.toLowerCase().contains(query);
  }

  static GlobalSearchResults search({
    required List<Restaurant> restaurants,
    required List<FoodItem> foodItems,
    required String query,
    DietMode dietMode = DietMode.nonVeg,
    int restaurantLimit = 15,
    int foodLimit = 25,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const GlobalSearchResults(restaurants: [], foodItems: []);
    }

    final matchedRestaurants = restaurants
        .where((r) {
          if (r.name.isEmpty) return false;
          if (dietMode == DietMode.veg && !r.isVeg) return false;
          if (dietMode == DietMode.nonVeg && r.isVeg) return false;
          return _contains(r.name, q) ||
              _contains(r.cuisine, q) ||
              _contains(r.city, q) ||
              _contains(r.address, q) ||
              _contains(r.description ?? '', q);
        })
        .take(restaurantLimit)
        .toList();

    final matchedFood = foodItems
        .where((f) {
          if (f.name.isEmpty) return false;
          if (!f.available || !f.inStock) return false;
          if (dietMode == DietMode.veg && !f.isVeg) return false;
          if (dietMode == DietMode.nonVeg && f.isVeg) return false;
          return _contains(f.name, q) ||
              _contains(f.restaurantName, q) ||
              _contains(f.categoryName, q) ||
              _contains(f.description, q) ||
              f.tags.any((tag) => _contains(tag, q));
        })
        .take(foodLimit)
        .toList();

    return GlobalSearchResults(
      restaurants: matchedRestaurants,
      foodItems: matchedFood,
    );
  }
}
