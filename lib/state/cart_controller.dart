import 'dart:async';
import 'package:flutter/material.dart';
import '../models/admin_models.dart';
import '../models/delivery_address.dart';
import '../models/food_item.dart';

export '../models/delivery_address.dart';

/// Result returned by [CartController.tryAddItem].
enum AddToCartResult {
  /// Item added successfully.
  added,

  /// No delivery address selected — prompt user to add one.
  noAddress,

  /// Cart already has items from a different restaurant — show clear-cart dialog.
  differentRestaurant,
}

class CartAddon {
  final String name;
  final int price;

  const CartAddon({required this.name, required this.price});
}

class CartLine {
  final FoodItem item;
  final int quantity;
  final List<CartAddon> addons;
  final String instructions;

  const CartLine({
    required this.item,
    required this.quantity,
    this.addons = const [],
    this.instructions = '',
  });

  int get unitTotal =>
      item.displayPrice + addons.fold(0, (s, a) => s + a.price);

  int get lineTotal => unitTotal * quantity;

  CartLine copyWith({
    FoodItem? item,
    int? quantity,
    List<CartAddon>? addons,
    String? instructions,
  }) {
    return CartLine(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
      addons: addons ?? this.addons,
      instructions: instructions ?? this.instructions,
    );
  }
}

class CitySurge {
  final String city;
  final int amount;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const CitySurge({
    required this.city,
    required this.amount,
    this.startsAt,
    this.endsAt,
  });
}

class CartController extends ChangeNotifier {
  final List<CartLine> _lines = [];
  DeliveryAddress? selectedAddress;
  PlatformCharges charges = const PlatformCharges();
  double? distanceKm;
  String surgeCity = '';
  List<CitySurge> activeSurges = const [];

  /// Periodic timer that ticks every 30 s so the UI rebuilds automatically
  /// when an active city surge crosses its [CitySurge.endsAt] deadline.
  Timer? _surgeExpiryTimer;

  /// When true delivery fee is always ₹0 (active subscription benefit).
  bool hasActiveSubscription = false;

  /// Guest identity until Auth is wired (Admin `orders.customerId`).
  String customerId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
  String customerName = 'Guest User';
  String customerPhone = ''; // populated from Firestore profile at checkout

  List<CartLine> get lines => List.unmodifiable(_lines);

  int get itemCount => _lines.fold(0, (s, l) => s + l.quantity);

  int get itemsTotal => _lines.fold(0, (s, l) => s + l.lineTotal);

  /// Sum of MRP (undiscounted) prices × quantity — shown as "Item Total" in the bill.
  int get itemsMrpTotal => itemsTotal + discount;

  /// Sum of per-item discounts (MRP - discounted price) × quantity.
  int get discount => _lines.fold(0, (s, l) {
    if (!l.item.hasDiscount) return s;
    return s + (l.item.price - l.item.displayPrice) * l.quantity;
  });

  /// Latest approved surge for [surgeCity] that has not reached its end time.
  int get activeCitySurge {
    final city = surgeCity.trim().toLowerCase();
    if (city.isEmpty) return 0;
    final now = DateTime.now();
    CitySurge? latest;
    for (final surge in activeSurges) {
      if (surge.city.trim().toLowerCase() != city) continue;
      final ends = surge.endsAt;
      if (ends == null || !ends.isAfter(now) || surge.amount <= 0) continue;
      if (latest == null) {
        latest = surge;
        continue;
      }
      final start = surge.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final latestStart =
          latest.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (start.isAfter(latestStart)) latest = surge;
    }
    return latest?.amount ?? 0;
  }

  int get deliveryFee {
    final base = hasActiveSubscription
        ? 0
        : charges.deliveryFeeFor(itemsTotal, distKm: distanceKm);
    return base + activeCitySurge;
  }

  int get taxes => charges.taxFor(itemsTotal);

  int get platformFee => charges.platformFee;

  int get grandTotal {
    // itemsMrpTotal = MRP total (before discount)
    // discount      = per-item price reduction already baked into itemsTotal
    // We start from itemsMrpTotal and subtract discount once, so the
    // "Discount" row in the UI is purely informational.
    final raw =
        itemsMrpTotal +
        deliveryFee +
        taxes +
        platformFee -
        discount +
        tipAmount;
    return (raw - walletApplied).clamp(0, raw);
  }

  int tipAmount = 0;

  void setTip(int amount) {
    tipAmount = amount < 0 ? 0 : amount;
    notifyListeners();
  }

  // ── Wallet ──────────────────────────────────────────────────────────────────

  /// The customer's current wallet balance loaded from Firestore.
  int walletBalance = 0;

  /// How much of the wallet the user has chosen to apply to this order.
  /// Capped at [walletBalance] and at the pre-wallet grand total.
  int get walletApplied => _walletApplied;
  int _walletApplied = 0;

  /// Whether the user has toggled wallet credit on.
  bool get walletEnabled => _walletApplied > 0;

  /// Call when the wallet stream emits a new balance.
  void setWalletBalance(int balance) {
    walletBalance = balance < 0 ? 0 : balance;
    // Re-clamp the applied amount if balance dropped.
    _recalcWallet();
    notifyListeners();
  }

  /// Toggle wallet credit on/off (applies full balance).
  void toggleWallet() {
    if (_walletApplied > 0) {
      _walletApplied = 0;
    } else {
      _recalcWallet(apply: true);
    }
    notifyListeners();
  }

  /// Apply a specific custom amount from the wallet.
  /// Capped at [walletBalance] and at the pre-wallet grand total.
  void setWalletApplied(int amount) {
    final preWallet =
        itemsMrpTotal +
        deliveryFee +
        taxes +
        platformFee -
        discount +
        tipAmount;
    _walletApplied = amount.clamp(0, walletBalance).clamp(0, preWallet);
    notifyListeners();
  }

  void _recalcWallet({bool apply = false}) {
    final preWallet =
        itemsMrpTotal +
        deliveryFee +
        taxes +
        platformFee -
        discount +
        tipAmount;
    if (apply) {
      // User explicitly toggled wallet on — apply the full available balance.
      _walletApplied = walletBalance.clamp(0, preWallet);
    } else {
      // Balance update from stream — only re-clamp what's already applied,
      // never increase it. This preserves any custom amount the user chose.
      _walletApplied = _walletApplied
          .clamp(0, walletBalance)
          .clamp(0, preWallet);
    }
  }

  int get totalAmount => grandTotal;

  bool get isEmpty => _lines.isEmpty;

  /// Total quantity of a specific food item across all cart lines.
  int countOf(String foodItemId) => _lines
      .where((l) => l.item.id == foodItemId)
      .fold(0, (s, l) => s + l.quantity);

  /// Replaces all lines for [foodItemId] with a single customised line.
  /// Returns false (and does nothing) if [item] belongs to a different
  /// restaurant than the items already in the cart.
  bool replaceItem({
    required String foodItemId,
    required FoodItem item,
    required int quantity,
    List<CartAddon> addons = const [],
    String instructions = '',
  }) {
    // Only block when the item being replaced is not already in the cart
    // (i.e. it's an add, not an edit of an existing line).
    final existsInCart = _lines.any((l) => l.item.id == foodItemId);
    if (!existsInCart &&
        _lines.isNotEmpty &&
        item.restaurantId.isNotEmpty &&
        currentRestaurantId.isNotEmpty &&
        item.restaurantId != currentRestaurantId) {
      return false; // different restaurant — caller should show clear-cart dialog
    }
    _lines.removeWhere((l) => l.item.id == foodItemId);
    if (quantity > 0) {
      _lines.add(
        CartLine(
          item: item,
          quantity: quantity,
          addons: addons,
          instructions: instructions,
        ),
      );
    }
    notifyListeners();
    return true;
  }

  /// Increments quantity of the last cart line for [foodItemId] by 1.
  void incrementItem(String foodItemId) {
    final idx = _lines.lastIndexWhere((l) => l.item.id == foodItemId);
    if (idx < 0) return;
    final line = _lines[idx];
    _lines[idx] = line.copyWith(quantity: line.quantity + 1);
    notifyListeners();
  }

  /// Decrements quantity of the last cart line for [foodItemId] by 1.
  /// Removes the line entirely when quantity reaches 0.
  void decrementItem(String foodItemId) {
    // Find the last matching line (most recently added).
    final idx = _lines.lastIndexWhere((l) => l.item.id == foodItemId);
    if (idx < 0) return;
    final line = _lines[idx];
    if (line.quantity <= 1) {
      _lines.removeAt(idx);
    } else {
      _lines[idx] = line.copyWith(quantity: line.quantity - 1);
    }
    notifyListeners();
  }

  bool get hasDeliveryAddress =>
      selectedAddress != null && selectedAddress!.isValid;

  /// The restaurantId of items currently in the cart. Empty if cart is empty.
  String get currentRestaurantId =>
      _lines.isEmpty ? '' : _lines.first.item.restaurantId;

  /// The restaurant name of items currently in the cart. Empty if cart is empty.
  String get currentRestaurantName =>
      _lines.isEmpty ? '' : _lines.first.item.restaurantName;

  String? get primaryRestaurantName =>
      _lines.isEmpty ? null : _lines.first.item.restaurantName;

  /// Restaurant logo/cover URL — set by CartSummaryScreen after fetching the restaurant doc.
  String restaurantImage = '';

  /// Restaurant coordinates — set by CartSummaryScreen for delivery partner assignment.
  double? restaurantLat;
  double? restaurantLng;
  String restaurantAddress = '';

  void setSubscriptionActive(bool value) {
    if (hasActiveSubscription == value) return;
    hasActiveSubscription = value;
    notifyListeners();
  }

  void applyCharges(PlatformCharges value) {
    charges = value;
    notifyListeners();
  }

  void setSurgeCity(String city) {
    final next = city.trim();
    if (surgeCity == next) return;
    surgeCity = next;
    notifyListeners();
  }

  void setActiveSurges(List<CitySurge> surges) {
    activeSurges = List.unmodifiable(surges);
    _rescheduleExpiryTimer();
    notifyListeners();
  }

  /// Starts (or restarts) a 30-second periodic timer that calls
  /// [notifyListeners] so widgets recompute [activeCitySurge] /
  /// [deliveryFee] / [grandTotal] automatically after a surge expires.
  /// The timer is cancelled when there are no active surges with a
  /// future [CitySurge.endsAt], or when the controller is disposed.
  void _rescheduleExpiryTimer() {
    _surgeExpiryTimer?.cancel();
    _surgeExpiryTimer = null;

    final now = DateTime.now();
    final hasLiveSurge = activeSurges.any((s) {
      final ends = s.endsAt;
      return ends != null && ends.isAfter(now) && s.amount > 0;
    });

    if (!hasLiveSurge) return;

    _surgeExpiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Check whether any surge is still live; cancel once all have expired.
      final stillLive = activeSurges.any((s) {
        final ends = s.endsAt;
        return ends != null && ends.isAfter(DateTime.now()) && s.amount > 0;
      });
      if (!stillLive) {
        _surgeExpiryTimer?.cancel();
        _surgeExpiryTimer = null;
      }
      notifyListeners(); // triggers rebuild → activeCitySurge recalculated
    });
  }

  @override
  void dispose() {
    _surgeExpiryTimer?.cancel();
    super.dispose();
  }

  void setDistanceKm(double? km) {
    if (distanceKm == km) return;
    distanceKm = km;
    notifyListeners();
  }

  void setCustomer({String? id, String? name, String? phone}) {
    if (id != null && id != customerId) {
      customerId = id;
      selectedAddress = null;
    } else if (id != null) {
      customerId = id;
    }
    if (name != null) customerName = name;
    // Only update phone if the new value is a real number (not placeholder zeros).
    if (phone != null && phone.isNotEmpty && !phone.contains('00000')) {
      customerPhone = phone;
    }
    notifyListeners();
  }

  /// Sync cart delivery address from Firestore list.
  /// Priority: keep current selection if still present → default → first.
  void syncAddressesFromFirestore(List<DeliveryAddress> addresses) {
    if (addresses.isEmpty) {
      if (selectedAddress != null) {
        selectedAddress = null;
        notifyListeners();
      }
      return;
    }

    // If there's already a valid address selected, keep it — whether it came
    // from Firestore (has an id) or from a GPS/manual pick (no id).
    // Only overwrite if the address is gone from the saved list.
    if (selectedAddress != null && selectedAddress!.isValid) {
      if (selectedAddress!.id.isNotEmpty) {
        final match = addresses
            .where((a) => a.id == selectedAddress!.id)
            .toList();
        if (match.isNotEmpty) {
          final next = match.first;
          if (next.fullAddress != selectedAddress!.fullAddress ||
              next.label != selectedAddress!.label ||
              next.isDefault != selectedAddress!.isDefault) {
            selectedAddress = next;
            notifyListeners();
          }
          return; // still present — keep it
        }
        // Address was deleted from Firestore — fall through to pick default
      } else {
        // GPS / unsaved address — keep it, don't overwrite with Firestore default
        return;
      }
    }

    // No address selected yet (or the saved one was deleted) — pick the default.
    selectedAddress = DeliveryAddress.pickPreferred(addresses);
    notifyListeners();
  }

  void setAddress(DeliveryAddress address) {
    selectedAddress = address;
    notifyListeners();
  }

  void clearAddress() {
    selectedAddress = null;
    distanceKm = null;
    notifyListeners();
  }

  // ── Multi-restaurant guard ──────────────────────────────────────────────────

  /// Returns [AddToCartResult.differentRestaurant] when the cart already has
  /// items from a different restaurant. The caller must then show a
  /// "Clear cart and switch?" dialog and call [clearAndAdd] on confirmation.
  ///
  /// Returns [AddToCartResult.noAddress] when no delivery address is selected.
  ///
  /// Returns [AddToCartResult.added] on success.
  AddToCartResult tryAddItem({
    required FoodItem item,
    int quantity = 1,
    List<CartAddon> addons = const [],
    String instructions = '',
  }) {
    if (!hasDeliveryAddress) return AddToCartResult.noAddress;

    // Block if the item belongs to a different restaurant.
    if (_lines.isNotEmpty &&
        item.restaurantId.isNotEmpty &&
        currentRestaurantId.isNotEmpty &&
        item.restaurantId != currentRestaurantId) {
      return AddToCartResult.differentRestaurant;
    }

    addItem(
      item: item,
      quantity: quantity,
      addons: addons,
      instructions: instructions,
    );
    return AddToCartResult.added;
  }

  void addItem({
    required FoodItem item,
    int quantity = 1,
    List<CartAddon> addons = const [],
    String instructions = '',
  }) {
    _lines.add(
      CartLine(
        item: item,
        quantity: quantity,
        addons: addons,
        instructions: instructions,
      ),
    );
    notifyListeners();
  }

  /// Clears the entire cart, then adds [item] as a fresh line.
  /// Call this after the user confirms "Yes, clear cart and switch restaurant".
  void clearAndAdd({
    required FoodItem item,
    int quantity = 1,
    List<CartAddon> addons = const [],
    String instructions = '',
  }) {
    _lines.clear();
    tipAmount = 0;
    _walletApplied = 0;
    restaurantImage = '';
    restaurantLat = null;
    restaurantLng = null;
    restaurantAddress = '';
    _lines.add(
      CartLine(
        item: item,
        quantity: quantity,
        addons: addons,
        instructions: instructions,
      ),
    );
    notifyListeners();
  }

  void updateQuantity(int index, int quantity) {
    if (index < 0 || index >= _lines.length) return;
    if (quantity <= 0) {
      _lines.removeAt(index);
    } else {
      _lines[index] = _lines[index].copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _lines.length) return;
    _lines.removeAt(index);
    notifyListeners();
  }

  Map<String, dynamic> toAdminOrderPayload({
    required String paymentMethod,
    required String orderId,
    Map<String, dynamic> extraFields = const {},
  }) {
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      items.add({
        'name': line.item.name,
        'qty': line.quantity,
        'price': line.item.displayPrice, // unit price — CF uses price × qty
      });
    }

    // Generate a unique 4-digit OTP for delivery verification.
    // Derived deterministically from the orderId so it's always the same
    // if the payload is rebuilt — no state needed.
    final otpBase = orderId.replaceAll(RegExp(r'\D'), '');
    final deliveryOtp = otpBase.length >= 4
        ? otpBase.substring(otpBase.length - 4)
        : (1000 + (orderId.hashCode.abs() % 9000)).toString();

    final addr = selectedAddress;
    return {
      'id': orderId,
      'orderNumber': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'restaurantId': _lines.isEmpty ? '' : _lines.first.item.restaurantId,
      'restaurantName': primaryRestaurantName ?? '',
      'restaurantImage': restaurantImage,
      'status': 'pending',
      'paymentMethod': paymentMethod,
      'items': items,
      'subtotal': itemsTotal,
      'tax': taxes,
      'deliveryFee': deliveryFee,
      'surgeFee': activeCitySurge, // stored separately for history breakdown
      'platformFee': platformFee,
      'discount': discount,
      'tip': tipAmount,
      'walletUsed': walletApplied,
      'total': grandTotal,
      'currency': 'INR',
      'address': addr?.fullAddress ?? '',
      if (addr != null)
        'deliveryAddress': {
          'id': addr.id,
          'label': addr.label,
          'fullAddress': addr.fullAddress,
          'isDefault': addr.isDefault,
          if (addr.lat != null) 'lat': addr.lat,
          if (addr.lng != null) 'lng': addr.lng,
        },
      'timeline': [
        {'status': 'pending', 'time': DateTime.now().toIso8601String()},
      ],
      // Restaurant location — required for nearest-partner auto-assignment in admin.
      if (restaurantLat != null) 'restaurantLat': restaurantLat,
      if (restaurantLng != null) 'restaurantLng': restaurantLng,
      if (restaurantAddress.isNotEmpty) 'restaurantAddress': restaurantAddress,
      // 4-digit OTP the customer shows to the delivery partner at drop-off.
      'deliveryOtp': deliveryOtp,
      // Caller-supplied overrides (e.g. paymentStatus for Razorpay flow).
      ...extraFields,
    };
  }

  void clear() {
    _lines.clear();
    // Keep selectedAddress — user's default address should persist across orders
    // so they don't need to re-select it every time.
    distanceKm = null;
    tipAmount = 0;
    _walletApplied = 0;
    // Keep walletBalance — it's refreshed by the live stream, not by orders.
    restaurantImage = '';
    restaurantLat = null;
    restaurantLng = null;
    restaurantAddress = '';
    // Do NOT reset customerId / customerName / customerPhone to guest values.
    // Resetting to a fake guest ID causes setCustomer() to think the user
    // changed and wipe selectedAddress on the very next call, breaking the
    // "address re-used on the next order" flow.
    notifyListeners();
  }
}

class CartScope extends InheritedNotifier<CartController> {
  const CartScope({
    super.key,
    required CartController controller,
    required super.child,
  }) : super(notifier: controller);

  static CartController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CartScope>();
    assert(scope != null, 'CartScope not found in widget tree');
    return scope!.notifier!;
  }

  static CartController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CartScope>()?.notifier;
  }
}
