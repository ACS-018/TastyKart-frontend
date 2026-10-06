import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/restaurant.dart';

/// Saved favourite store entry on Admin `customers/{id}.favorites`.
class FavoriteRestaurant {
  final String restaurantId;
  final String restaurantName;
  final String cuisine;
  final String imageUrl;
  final double rating;
  final String deliveryTime;
  final DateTime? addedAt;

  const FavoriteRestaurant({
    required this.restaurantId,
    required this.restaurantName,
    this.cuisine = '',
    this.imageUrl = '',
    this.rating = 0,
    this.deliveryTime = '',
    this.addedAt,
  });

  factory FavoriteRestaurant.fromMap(Map<String, dynamic> map) {
    return FavoriteRestaurant(
      restaurantId:
          _stringField(map, 'restaurantId') ?? _stringField(map, 'id') ?? '',
      restaurantName:
          _stringField(map, 'restaurantName') ?? _stringField(map, 'name') ?? '',
      cuisine: _stringField(map, 'cuisine') ?? '',
      imageUrl: _stringField(map, 'imageUrl') ??
          _stringField(map, 'image') ??
          _stringField(map, 'cover') ??
          '',
      rating: (map['rating'] as num? ?? 0).toDouble(),
      deliveryTime: map['deliveryTime']?.toString() ?? '',
      addedAt: _parseDate(map['addedAt']),
    );
  }

  factory FavoriteRestaurant.fromRestaurant(
    Restaurant restaurant, {
    String? restaurantId,
  }) {
    return FavoriteRestaurant(
      restaurantId: restaurantId ?? restaurant.id,
      restaurantName: restaurant.name,
      cuisine: restaurant.cuisine,
      imageUrl: restaurant.imageUrl,
      rating: restaurant.rating,
      deliveryTime: restaurant.deliveryTime,
      addedAt: DateTime.now(),
    );
  }

  static String? _stringField(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> toMap() {
    return {
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'cuisine': cuisine,
      'imageUrl': imageUrl,
      'rating': rating,
      'deliveryTime': deliveryTime,
      'addedAt': addedAt?.toIso8601String(),
    };
  }

  Restaurant toRestaurant() {
    return Restaurant(
      id: restaurantId,
      name: restaurantName,
      cuisine: cuisine,
      cover: imageUrl.isNotEmpty ? imageUrl : null,
      address: '',
      city: '',
      rating: rating,
      totalOrders: 0,
      status: 'active',
      phone: '',
      openingHours: '',
      deliveryTime: deliveryTime,
      minOrder: 0,
      isVeg: false,
      featured: false,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse(value.toString());
  }
}
