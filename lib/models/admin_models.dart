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

  const PlatformCharges({
    this.baseDeliveryFee = 40,
    this.maxDeliveryFee = 80,
    this.platformFee = 0,
    this.freeDeliveryThreshold = 299,
    this.minOrderValue = 0,
    this.gstRate = 5,
  });

  factory PlatformCharges.fromSettingsDoc(DocumentSnapshot? doc) {
    if (doc == null || !doc.exists) return const PlatformCharges();
    final root = doc.data() as Map<String, dynamic>? ?? {};
    final charges = root['charges'] as Map<String, dynamic>? ?? {};
    final tax = root['tax'] as Map<String, dynamic>? ?? {};
    return PlatformCharges(
      baseDeliveryFee: (charges['baseDeliveryFee'] as num? ?? 40).toInt(),
      maxDeliveryFee: (charges['maxDeliveryFee'] as num? ?? 80).toInt(),
      platformFee: (charges['platformFee'] as num? ?? 0).toInt(),
      freeDeliveryThreshold:
          (charges['freeDeliveryThreshold'] as num? ?? 299).toInt(),
      minOrderValue: (charges['minOrderValue'] as num? ?? 0).toInt(),
      gstRate: (tax['gstRate'] as num? ?? 5).toDouble(),
    );
  }

  int deliveryFeeFor(int itemsTotal) {
    if (freeDeliveryThreshold > 0 && itemsTotal >= freeDeliveryThreshold) {
      return 0;
    }
    return baseDeliveryFee.clamp(0, maxDeliveryFee);
  }

  int taxFor(int itemsTotal) =>
      ((itemsTotal * gstRate) / 100).round();
}

/// Admin-compatible order summary for history UI.
class TkOrder {
  final String id;
  final String orderNumber;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String restaurantName;
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
  final DateTime? createdAt;

  const TkOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.restaurantName,
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
    this.createdAt,
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
      restaurantName: d['restaurantName'] as String? ?? '',
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
      createdAt: created,
    );
  }
}
