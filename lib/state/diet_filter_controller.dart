import 'package:flutter/material.dart';

import '../models/food_item.dart';
import '../models/restaurant.dart';

/// App-wide veg / non-veg preference from the home toggle.
enum DietMode { veg, nonVeg }

class DietFilterController extends ChangeNotifier {
  DietMode _mode = DietMode.nonVeg;

  DietMode get mode => _mode;

  bool get isVegMode => _mode == DietMode.veg;

  void setVegMode(bool veg) {
    final next = veg ? DietMode.veg : DietMode.nonVeg;
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }

  bool matchesRestaurant(Restaurant restaurant) {
    // When veg mode is on, only hide restaurants that are explicitly marked
    // as non-veg (isVeg == false is the default and not a reliable signal
    // because most restaurants don't set this flag).
    // In practice: veg mode shows all restaurants (food-level filtering
    // handles what items are visible inside). Non-veg mode shows everything.
    //
    // We intentionally do NOT filter restaurants out based on isVeg because:
    //  • Restaurants are not created with isVeg set during normal admin flow.
    //  • A mixed restaurant (serves both) should still appear in veg mode.
    //  • Food-item level filtering via matchesFood() handles the actual restriction.
    return true;
  }

  bool matchesFood(FoodItem item) {
    // Veg mode: show only veg items
    // Non-veg mode: show all items (both veg and non-veg)
    return _mode == DietMode.veg ? item.isVeg : true;
  }
}

class DietFilterScope extends InheritedNotifier<DietFilterController> {
  const DietFilterScope({
    super.key,
    required DietFilterController controller,
    required super.child,
  }) : super(notifier: controller);

  static DietFilterController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DietFilterScope>();
    assert(scope != null, 'DietFilterScope not found in widget tree');
    return scope!.notifier!;
  }

  static DietFilterController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DietFilterScope>()
        ?.notifier;
  }
}
