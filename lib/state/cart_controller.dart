import 'package:flutter/material.dart';
import '../models/admin_models.dart';
import '../models/delivery_address.dart';
import '../models/food_item.dart';

export '../models/delivery_address.dart';

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

class CartController extends ChangeNotifier {
  final List<CartLine> _lines = [];
  DeliveryAddress? selectedAddress;
  PlatformCharges charges = const PlatformCharges();

  /// Guest identity until Auth is wired (Admin `orders.customerId`).
  String customerId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
  String customerName = 'Guest User';
  String customerPhone = '+91 00000 00000';

  List<CartLine> get lines => List.unmodifiable(_lines);

  int get itemCount => _lines.fold(0, (s, l) => s + l.quantity);

  int get itemsTotal => _lines.fold(0, (s, l) => s + l.lineTotal);

  int get discount => 0;

  int get deliveryFee => charges.deliveryFeeFor(itemsTotal);

  int get taxes => charges.taxFor(itemsTotal);

  int get platformFee => charges.platformFee;

  int get packingCharges => 0;

  int get grandTotal =>
      itemsTotal + deliveryFee + taxes + platformFee + packingCharges - discount;

  int get totalAmount => grandTotal;

  bool get isEmpty => _lines.isEmpty;

  bool get hasDeliveryAddress =>
      selectedAddress != null && selectedAddress!.isValid;

  String? get primaryRestaurantName =>
      _lines.isEmpty ? null : _lines.first.item.restaurantName;

  void applyCharges(PlatformCharges value) {
    charges = value;
    notifyListeners();
  }

  void setCustomer({
    String? id,
    String? name,
    String? phone,
  }) {
    if (id != null && id != customerId) {
      customerId = id;
      selectedAddress = null;
    } else if (id != null) {
      customerId = id;
    }
    if (name != null) customerName = name;
    if (phone != null) customerPhone = phone;
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

    if (selectedAddress?.id.isNotEmpty == true) {
      final match =
          addresses.where((a) => a.id == selectedAddress!.id).toList();
      if (match.isNotEmpty) {
        final next = match.first;
        if (next.fullAddress != selectedAddress!.fullAddress ||
            next.label != selectedAddress!.label ||
            next.isDefault != selectedAddress!.isDefault) {
          selectedAddress = next;
          notifyListeners();
        }
        return;
      }
    }

    selectedAddress = DeliveryAddress.pickPreferred(addresses);
    notifyListeners();
  }

  void setAddress(DeliveryAddress address) {
    selectedAddress = address;
    notifyListeners();
  }

  void clearAddress() {
    selectedAddress = null;
    notifyListeners();
  }

  /// Returns false when no delivery address is selected — caller must prompt.
  bool tryAddItem({
    required FoodItem item,
    int quantity = 1,
    List<CartAddon> addons = const [],
    String instructions = '',
  }) {
    if (!hasDeliveryAddress) return false;
    addItem(
      item: item,
      quantity: quantity,
      addons: addons,
      instructions: instructions,
    );
    return true;
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
  }) {
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      items.add({
        'name': line.item.name,
        'qty': line.quantity,
        'price': line.unitTotal,
      });
    }

    final addr = selectedAddress;
    return {
      'id': orderId,
      'orderNumber': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'restaurantId': _lines.isEmpty ? '' : _lines.first.item.restaurantId,
      'restaurantName': primaryRestaurantName ?? '',
      'status': 'pending',
      'paymentMethod': paymentMethod,
      'items': items,
      'subtotal': itemsTotal,
      'tax': taxes,
      'deliveryFee': deliveryFee,
      'platformFee': platformFee,
      'discount': discount,
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
    };
  }

  void clear() {
    _lines.clear();
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
