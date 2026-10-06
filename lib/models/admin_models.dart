import 'package:cloud_firestore/cloud_firestore.dart';

/// Matches Admin `foodCategories` (restaurant-scoped menu sections).
class FoodCategory {
  final String id;
  final String name;
  final String restaurantId;
  final String restaurantName;
  final String? icon;
  final String? image;
  final String status;
  final String? description;
  final int sortOrder;
  final int itemCount;

  const FoodCategory({
    required this.id,
    required this.name,
    this.restaurantId = '',
    this.restaurantName = '',
    this.icon,
    this.image,
    required this.status,
    this.description,
    this.sortOrder = 0,
    this.itemCount = 0,
  });

  String get imageUrl =>
      (image != null && image!.isNotEmpty) ? image! : (icon ?? '');

  factory FoodCategory.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return FoodCategory(
      id: d['id'] as String? ?? doc.id,
      name: d['name'] as String? ?? '',
      restaurantId: d['restaurantId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String? ?? '',
      icon: d['icon'] as String?,
      image: d['image'] as String?,
      status: d['status'] as String? ?? 'active',
      description: d['description'] as String?,
      sortOrder: (d['sortOrder'] as num? ?? 0).toInt(),
      itemCount: (d['itemCount'] as num? ?? 0).toInt(),
    );
  }
}

/// Matches Admin `addons`.
class AddonItem {
  final String id;
  final String name;
  final int price;
  final String? category;
  final String status;
  final String? description;
  final String? restaurantId;

  const AddonItem({
    required this.id,
    required this.name,
    required this.price,
    this.category,
    required this.status,
    this.description,
    this.restaurantId,
  });

  factory AddonItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AddonItem(
      id: d['id'] as String? ?? doc.id,
      name: d['name'] as String? ?? '',
      price: (d['price'] as num? ?? 0).toInt(),
      category: d['category'] as String?,
      status: d['status'] as String? ?? 'active',
      description: d['description'] as String?,
      restaurantId: d['restaurantId'] as String?,
    );
  }
}

/// Matches Admin `notifications`.
class AppNotification {
  final String id;
  final String title;
  final String message;
  final String type;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.read,
    this.createdAt,
  });

  factory AppNotification.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? created;
    final raw = d['createdAt'];
    if (raw is Timestamp) {
      created = raw.toDate();
    } else if (raw is String) {
      created = DateTime.tryParse(raw);
    }
    return AppNotification(
      id: d['id'] as String? ?? doc.id,
      title: d['title'] as String? ?? '',
      message: d['message'] as String? ?? '',
      type: d['type'] as String? ?? 'info',
      read: d['read'] as bool? ?? false,
      createdAt: created,
    );
  }

  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min Ago';
    if (diff.inHours < 24) return '${diff.inHours} Hrs Ago';
    return '${diff.inDays} Days Ago';
  }
}

/// Platform charges from `settings/admin` (Admin Settings page).
class PlatformCharges {
  final int baseDeliveryFee;
  final int maxDeliveryFee;
  final int platformFee;
  final int freeDeliveryThreshold;
  final int minOrderValue;
  final double gstRate;
  final double surgeMultiplier;

  /// Per-km delivery rate — from `deliveryPartner.perKmRate` in settings/admin.
  final int perKmRate;

  /// Minutes the delivery partner waits at restaurant after the prep timer
  /// expires before the "Transfer Order" option appears.
  /// Read from `settings/admin → delivery.partnerWaitMinutes`.
  final int partnerWaitMinutes;

  const PlatformCharges({
    this.baseDeliveryFee = 20,
    this.maxDeliveryFee = 80,
    this.platformFee = 0,
    this.freeDeliveryThreshold = 299,
    this.minOrderValue = 0,
    this.gstRate = 5,
    this.surgeMultiplier = 1.0,
    this.perKmRate = 10,
    this.partnerWaitMinutes = 10,
  });

  factory PlatformCharges.fromSettingsDoc(DocumentSnapshot? doc) {
    if (doc == null || !doc.exists) return const PlatformCharges();
    final root = doc.data() as Map<String, dynamic>? ?? {};
    final charges = root['charges'] as Map<String, dynamic>? ?? {};
    final tax = root['tax'] as Map<String, dynamic>? ?? {};
    // perKmRate can live under charges (preferred) or legacy deliveryPartner map.
    final partner = root['deliveryPartner'] as Map<String, dynamic>? ?? {};

    // Safety guard: guardrails against obviously-invalid admin values
    // (e.g. freeDeliveryThreshold=1 would make every order free).
    final rawThreshold = (charges['freeDeliveryThreshold'] as num? ?? 299)
        .toInt();
    final safeThreshold = rawThreshold < 100 ? 299 : rawThreshold;

    // perKmRate: read deliveryFeePerKm (Admin field name) first.
    // Use toString + int.tryParse to handle any Firestore type (int, double, String).
    int parseRate(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final perKmRate = [
      parseRate(charges['deliveryFeePerKm']),
      parseRate(charges['perKmRate']),
      parseRate(partner['perKmRate']),
    ].firstWhere((v) => v > 0, orElse: () => 10);

    return PlatformCharges(
      baseDeliveryFee: parseRate(charges['baseDeliveryFee']) > 0
          ? parseRate(charges['baseDeliveryFee'])
          : 20,
      maxDeliveryFee: parseRate(charges['maxDeliveryFee']) > 0
          ? parseRate(charges['maxDeliveryFee'])
          : 80,
      platformFee: parseRate(charges['platformFee']),
      freeDeliveryThreshold: safeThreshold,
      minOrderValue: parseRate(charges['minOrderValue']),
      gstRate: ((tax['gstRate'] ?? charges['gstRate']) as num? ?? 5).toDouble(),
      surgeMultiplier: (charges['surgeMultiplier'] as num? ?? 1.0).toDouble(),
      perKmRate: perKmRate,
      // Read from delivery.partnerWaitMinutes; default 10 min.
      partnerWaitMinutes: (() {
        final delivery = root['delivery'] as Map<String, dynamic>? ?? {};
        final raw = delivery['partnerWaitMinutes'];
        if (raw is num) return raw.toInt().clamp(1, 120);
        return 10;
      })(),
    );
  }

  /// Calculates delivery fee.
  ///
  /// Formula:  `baseDeliveryFee + (perKmRate × distKm)` × surgeMultiplier
  ///   rounded up, clamped to `[0, maxDeliveryFee]`.
  ///
  /// When distance is unknown, uses the flat `baseDeliveryFee` and respects
  /// the free-delivery threshold (guarded to a sane minimum).
  ///
  /// Example with defaults (base=20, perKm=10):
  ///   3 km → 20 + (10×3) = ₹50
  ///   5 km → 20 + (10×5) = ₹70 (clamped to maxDeliveryFee if exceeded)
  int deliveryFeeFor(int itemsTotal, {double? distKm}) {
    // Free delivery threshold always takes priority — regardless of distance.
    if (freeDeliveryThreshold > 0 && itemsTotal >= freeDeliveryThreshold) {
      return 0;
    }
    if (distKm != null && distKm > 0) {
      // Formula: baseDeliveryFee + (perKmRate × distKm), no surge applied.
      final total = baseDeliveryFee + (perKmRate * distKm);
      return total.ceil().clamp(0, maxDeliveryFee);
    }
    // No distance known — flat base fee.
    return baseDeliveryFee.clamp(0, maxDeliveryFee);
  }

  int taxFor(int itemsTotal) => ((itemsTotal * gstRate) / 100).round();
}

/// Admin-compatible order summary for history UI.
class TkOrder {
  final String id;
  final String orderNumber;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String restaurantId;
  final String restaurantName;
  final String restaurantImage;
  final String status;
  final String paymentMethod;
  final List<Map<String, dynamic>> items;
  final int subtotal;
  final int tax;
  final int deliveryFee;
  final int platformFee;
  final int discount;
  final int total;
  final String address;
  /// Label of the saved address — e.g. "Home", "Work" (from deliveryAddress.label).
  final String addressLabel;
  final DateTime? createdAt;
  final String deliveryOtp;
  final String deliveryPartnerName;
  final String deliveryStage;
  final String deliveryPartnerId;
  final String deliveryPartnerPhone;
  final double? destLat;
  final double? destLng;

  /// Tip the customer added for the delivery partner (Firestore key: `tip`).
  final int tip;

  /// City-surge component baked into [deliveryFee] at checkout time
  /// (Firestore key: `surgeFee`). Stored separately so the history UI can
  /// display it as a distinct line item.
  final int surgeFee;

  /// Wallet credit applied at checkout (Firestore key: `walletUsed`).
  /// Positive value = deducted from wallet to reduce the grand total.
  final int walletUsed;

  const TkOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.restaurantId = '',
    required this.restaurantName,
    this.restaurantImage = '',
    required this.status,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.deliveryFee,
    required this.platformFee,
    required this.discount,
    required this.total,
    required this.address,
    this.addressLabel = '',
    this.createdAt,
    this.deliveryOtp = '',
    this.deliveryPartnerName = '',
    this.deliveryStage = '',
    this.deliveryPartnerId = '',
    this.deliveryPartnerPhone = '',
    this.destLat,
    this.destLng,
    this.tip = 0,
    this.surgeFee = 0,
    this.walletUsed = 0,
  });

  factory TkOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? created;
    final raw = d['createdAt'];
    if (raw is Timestamp) created = raw.toDate();

    final itemsRaw = d['items'] as List? ?? [];
    final items = itemsRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return TkOrder(
      id: d['id'] as String? ?? doc.id,
      orderNumber: d['orderNumber'] as String? ?? d['id'] as String? ?? doc.id,
      customerId: d['customerId'] as String? ?? '',
      customerName: d['customerName'] as String? ?? '',
      customerPhone: d['customerPhone'] as String? ?? '',
      restaurantId: d['restaurantId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String? ?? '',
      restaurantImage: d['restaurantImage'] as String? ?? '',
      status: d['status'] as String? ?? 'pending',
      paymentMethod: d['paymentMethod'] as String? ?? '',
      items: items,
      subtotal: (d['subtotal'] as num? ?? 0).toInt(),
      tax: (d['tax'] as num? ?? 0).toInt(),
      deliveryFee: (d['deliveryFee'] as num? ?? 0).toInt(),
      platformFee: (d['platformFee'] as num? ?? 0).toInt(),
      discount: (d['discount'] as num? ?? 0).toInt(),
      total: (d['total'] as num? ?? 0).toInt(),
      address: d['address'] as String? ?? '',
      addressLabel: (() {
        final da = d['deliveryAddress'];
        if (da is Map) return (da['label'] as String? ?? '').trim();
        return '';
      })(),
      createdAt: created,
      deliveryOtp: d['deliveryOtp'] as String? ?? '',
      deliveryPartnerName: d['deliveryPartnerName'] as String? ?? '',
      deliveryStage: d['deliveryStage'] as String? ?? '',
      deliveryPartnerId: d['deliveryPartnerId'] as String? ?? '',
      deliveryPartnerPhone: d['deliveryPartnerPhone'] as String? ?? '',
      destLat: (d['destLat'] as num?)?.toDouble(),
      destLng: (d['destLng'] as num?)?.toDouble(),
      tip: ((d['tip']) as num? ?? 0).toInt(),
      surgeFee: ((d['surgeFee']) as num? ?? 0).toInt(),
      walletUsed: ((d['walletUsed']) as num? ?? 0).toInt(),
    );
  }
}
