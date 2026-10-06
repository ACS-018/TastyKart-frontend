import 'package:cloud_firestore/cloud_firestore.dart';

class FoodItem {
  final String id;
  final String name;
  final String description;
  final String image;
  final String categoryId;
  final String categoryName;
  final String restaurantId;
  final String restaurantName;
  final int price;
  final int discountedPrice;
  final int preparationTime;
  final double rating;
  final int totalRatings;
  final bool isVeg;
  final bool available;
  final bool inStock;
  final List<String> tags;
  final String status;

  const FoodItem({
    required this.id,
    required this.name,
    required this.description,
    required this.image,
    required this.categoryId,
    required this.categoryName,
    required this.restaurantId,
    required this.restaurantName,
    required this.price,
    required this.discountedPrice,
    required this.preparationTime,
    required this.rating,
    required this.totalRatings,
    required this.isVeg,
    required this.available,
    required this.inStock,
    required this.tags,
    required this.status,
  });

  int get displayPrice =>
      discountedPrice > 0 && discountedPrice < price ? discountedPrice : price;

  bool get hasDiscount => discountedPrice > 0 && discountedPrice < price;

  int get discountPercent =>
      hasDiscount ? (((price - discountedPrice) / price) * 100).round() : 0;

  /// Returns a copy of this item with [offerPrice] as the effective unit price.
  ///
  /// Sets [discountedPrice] so that [displayPrice] == [offerPrice], which
  /// means the cart line stores the offer-discounted price without any
  /// special handling in [CartController].
  FoodItem withOfferPrice(int offerPrice) {
    // Clamp: offer cannot exceed the original price.
    final clamped = offerPrice.clamp(0, price);
    return FoodItem(
      id: id,
      name: name,
      description: description,
      image: image,
      categoryId: categoryId,
      categoryName: categoryName,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      price: price,
      discountedPrice: clamped,
      preparationTime: preparationTime,
      rating: rating,
      totalRatings: totalRatings,
      isVeg: isVeg,
      available: available,
      inStock: inStock,
      tags: tags,
      status: status,
    );
  }

  factory FoodItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return FoodItem(
      id: d['id'] as String? ?? doc.id,
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      image: (d['imageUrl'] ?? d['image'] ?? '') as String,
      categoryId: d['categoryId'] as String? ?? '',
      categoryName: d['categoryName'] as String? ?? '',
      restaurantId: d['restaurantId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String? ?? '',
      price: (d['price'] as num? ?? 0).toInt(),
      discountedPrice: (d['discountedPrice'] as num? ?? 0).toInt(),
      preparationTime: (d['preparationTime'] as num? ?? 0).toInt(),
      rating: (d['rating'] as num? ?? 0).toDouble(),
      totalRatings: (d['totalRatings'] as num? ?? 0).toInt(),
      isVeg: d['isVeg'] as bool? ?? false,
      available: d['available'] as bool? ?? true,
      inStock: d['inStock'] as bool? ?? true,
      tags: List<String>.from(d['tags'] as List? ?? []),
      status: d['status'] as String? ?? '',
    );
  }
}
