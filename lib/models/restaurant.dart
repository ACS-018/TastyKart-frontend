import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin `restaurants/{id}` — see admin.md §7.2.
class Restaurant {
  final String id;
  final String name;
  final String? logo;
  final String? cover;
  final String cuisine;
  final String address;
  final String city;
  final double rating;
  final int totalOrders;
  final String status;
  final String phone;
  final String openingHours;
  final String deliveryTime;
  final int minOrder;
  final bool isVeg;
  final bool featured;
  final String? description;

  const Restaurant({
    required this.id,
    required this.name,
    this.logo,
    this.cover,
    required this.cuisine,
    required this.address,
    required this.city,
    required this.rating,
    required this.totalOrders,
    required this.status,
    required this.phone,
    required this.openingHours,
    required this.deliveryTime,
    required this.minOrder,
    required this.isVeg,
    required this.featured,
    this.description,
  });

  String get imageUrl {
    if (cover != null && cover!.isNotEmpty) return cover!;
    if (logo != null && logo!.isNotEmpty) return logo!;
    return '';
  }

  String get locationLabel {
    if (city.isNotEmpty && address.isNotEmpty) return '$city';
    if (city.isNotEmpty) return city;
    return address;
  }

  factory Restaurant.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Restaurant(
      id: d['id'] as String? ?? doc.id,
      name: d['name'] as String? ?? '',
      logo: d['logo'] as String?,
      cover: d['cover'] as String?,
      cuisine: d['cuisine'] as String? ?? '',
      address: d['address'] as String? ?? '',
      city: d['city'] as String? ?? '',
      rating: (d['rating'] as num? ?? 0).toDouble(),
      totalOrders: (d['totalOrders'] as num? ?? 0).toInt(),
      status: d['status'] as String? ?? 'active',
      phone: d['phone'] as String? ?? '',
      openingHours: d['openingHours'] as String? ?? '',
      deliveryTime: d['deliveryTime']?.toString() ?? '30-40 Min',
      minOrder: (d['minOrder'] as num? ?? 0).toInt(),
      isVeg: d['isVeg'] as bool? ?? false,
      featured: d['featured'] as bool? ?? false,
      description: d['description'] as String?,
    );
  }
}

/// Admin `restaurantCategories` — global cuisine chips on Home Explore.
class RestaurantCategory {
  final String id;
  final String name;
  final String? icon;
  final String? image;
  final String status;
  final int restaurantCount;

  const RestaurantCategory({
    required this.id,
    required this.name,
    this.icon,
    this.image,
    required this.status,
    this.restaurantCount = 0,
  });

  String get imageUrl {
    if (image != null && image!.isNotEmpty) return image!;
    if (icon != null && icon!.isNotEmpty && icon!.startsWith('http')) {
      return icon!;
    }
    return '';
  }

  factory RestaurantCategory.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return RestaurantCategory(
      id: d['id'] as String? ?? doc.id,
      name: d['name'] as String? ?? '',
      icon: d['icon'] as String?,
      image: d['image'] as String?,
      status: d['status'] as String? ?? 'active',
      restaurantCount: (d['restaurantCount'] as num? ?? 0).toInt(),
    );
  }
}
