import 'package:flutter/material.dart';

import '../models/favorite_restaurant.dart';
import '../models/restaurant.dart';
import '../services/favorites_service.dart';

class FavoritesController extends ChangeNotifier {
  List<FavoriteRestaurant> _favorites = const [];

  List<FavoriteRestaurant> get favorites => List.unmodifiable(_favorites);

  bool get isEmpty => _favorites.isEmpty;

  bool isFavorite(String restaurantId) {
    if (restaurantId.isEmpty) return false;
    return _favorites.any((f) => f.restaurantId == restaurantId);
  }

  void syncFromFirestore(List<FavoriteRestaurant> list) {
    _favorites = list;
    notifyListeners();
  }

  void clear() {
    _favorites = const [];
    notifyListeners();
  }

  Future<void> toggle(Restaurant restaurant) async {
    final restaurantId = restaurant.id.trim();
    if (restaurantId.isEmpty) return;

    final wasFavorite = isFavorite(restaurantId);
    if (wasFavorite) {
      _favorites =
          _favorites.where((f) => f.restaurantId != restaurantId).toList();
    } else {
      _favorites = [
        FavoriteRestaurant.fromRestaurant(restaurant),
        ..._favorites,
      ];
    }
    notifyListeners();

    try {
      await FavoritesService.toggleRestaurant(restaurant);
    } catch (e) {
      if (wasFavorite) {
        _favorites = [
          FavoriteRestaurant.fromRestaurant(restaurant),
          ..._favorites,
        ];
      } else {
        _favorites =
            _favorites.where((f) => f.restaurantId != restaurantId).toList();
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> remove(String restaurantId) async {
    final previous = _favorites;
    _favorites =
        _favorites.where((f) => f.restaurantId != restaurantId).toList();
    notifyListeners();

    try {
      await FavoritesService.removeRestaurant(restaurantId);
    } catch (e) {
      _favorites = previous;
      notifyListeners();
      rethrow;
    }
  }
}

class FavoritesScope extends InheritedNotifier<FavoritesController> {
  const FavoritesScope({
    super.key,
    required FavoritesController controller,
    required super.child,
  }) : super(notifier: controller);

  static FavoritesController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FavoritesScope>();
    assert(scope != null, 'FavoritesScope not found in widget tree');
    return scope!.notifier!;
  }

  static FavoritesController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FavoritesScope>()?.notifier;
  }
}
