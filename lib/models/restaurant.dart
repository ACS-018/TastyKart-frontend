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

  /// Dynamic average rating computed from user submissions.
  /// Firestore field: `averageRating` (written by [FirestoreService.submitRestaurantRating]).
  /// Falls back to the static seed `rating` field when no user reviews exist yet.
  final double rating;

  /// Total number of user-submitted ratings.
  /// Firestore field: `totalReviews`.
  final int totalReviews;

  final int totalOrders;
  final String status;
  final String phone;
  final String openingHours;
  final String deliveryTime;
  final int minOrder;
  final bool isVeg;
  final bool featured;

  /// Admin flag. Search shows these under Popular restaurants.
  final bool popular;
  final String? description;
  final double? lat;
  final double? lng;

  /// IDs of `restaurantCategories` assigned in Admin.
  /// Firestore field: `categories: string[]`
  final List<String> categories;

  const Restaurant({
    required this.id,
    required this.name,
    this.logo,
    this.cover,
    required this.cuisine,
    required this.address,
    required this.city,
    required this.rating,
    this.totalReviews = 0,
    required this.totalOrders,
    required this.status,
    required this.phone,
    required this.openingHours,
    required this.deliveryTime,
    required this.minOrder,
    required this.isVeg,
    required this.featured,
    this.popular = false,
    this.description,
    this.lat,
    this.lng,
    this.categories = const [],
  });

  String get imageUrl {
    if (cover != null && cover!.isNotEmpty) return cover!;
    if (logo != null && logo!.isNotEmpty) return logo!;
    return '';
  }

  String get locationLabel {
    if (city.isNotEmpty && address.isNotEmpty) return city;
    if (city.isNotEmpty) return city;
    return address;
  }

  factory Restaurant.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final idField = d['id'] as String?;

    // Try location sub-map first for a more accurate address.
    final loc = d['location'] as Map<String, dynamic>?;
    final locationAddress =
        (loc?['address'] as String?) ?? (d['address'] as String? ?? '');

    // Extract city from the full address string:
    // e.g. "C94G+FG2, Marrichettu, Hyderabad, Telangana 500089, India"
    //  → parts[-3] = "Hyderabad"
    String cityFromAddress(String fullAddr) {
      final parts = fullAddr
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      // Standard Indian format ends in: ..., City, State Pincode, Country
      // So city is parts[length - 3] when length >= 3.
      if (parts.length >= 3) {
        // Skip parts that look like PIN codes or are 'India'
        // Walk backwards: skip country, skip state+pin, take city
        return parts[parts.length - 3];
      }
      if (parts.length == 2) return parts[0];
      return fullAddr;
    }

    // Use city field if it matches the address; otherwise derive from address.
    final rawCity = (d['city'] as String? ?? '').trim();
    final derivedCity = locationAddress.isNotEmpty
        ? cityFromAddress(locationAddress)
        : rawCity;
    // Prefer derived city (from actual coordinates address) over the stored city field.
    final city = derivedCity.isNotEmpty ? derivedCity : rawCity;
    return Restaurant(
      id: (idField != null && idField.trim().isNotEmpty) ? idField : doc.id,
      name: d['name'] as String? ?? '',
      logo: d['logo'] as String?,
      cover: d['cover'] as String?,
      cuisine: d['cuisine'] as String? ?? '',
      address: locationAddress.isNotEmpty
          ? locationAddress
          : (d['address'] as String? ?? ''),
      city: city,
      // Prefer the dynamically computed average from user reviews.
      // `averageRating` is written by FirestoreService.submitRestaurantRating().
      // Fall back to the static seed `rating` field when no user reviews exist.
      rating: ((d['averageRating'] ?? d['rating']) as num? ?? 0).toDouble(),
      totalReviews: (d['totalReviews'] as num? ?? 0).toInt(),
      totalOrders: (d['totalOrders'] as num? ?? 0).toInt(),
      status: d['status'] as String? ?? 'active',
      phone: d['phone'] as String? ?? '',
      openingHours: d['openingHours'] as String? ?? '',
      deliveryTime: d['deliveryTime']?.toString() ?? '30-40 Min',
      minOrder: (d['minOrder'] as num? ?? 0).toInt(),
      isVeg: d['isVeg'] as bool? ?? false,
      featured: d['featured'] as bool? ?? false,
      popular: d['popular'] as bool? ?? false,
      description: d['description'] as String?,
      lat: _parseCoord(d, 'lat', 'latitude'),
      lng: _parseCoord(d, 'lng', 'longitude'),
      categories: (d['categories'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Reads a coordinate from the root OR from the nested `location` map.
  static double? _parseCoord(
    Map<String, dynamic> d,
    String shortKey,
    String longKey,
  ) {
    // Try root-level first (legacy / manually set)
    final root = (d[shortKey] ?? d[longKey] as num?)?.toDouble();
    if (root != null) return root;
    // Then try location sub-map (Admin app writes location.latitude / location.longitude)
    final loc = d['location'] as Map<String, dynamic>?;
    return (loc?[shortKey] ?? loc?[longKey] as num?)?.toDouble();
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
  final int sortOrder;

  const RestaurantCategory({
    required this.id,
    required this.name,
    this.icon,
    this.image,
    required this.status,
    this.restaurantCount = 0,
    this.sortOrder = 0,
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
      // Always use the Firestore document ID so it matches what the admin
      // stores in restaurant.categories[] (which uses the Firestore doc ID,
      // not the optional 'id' field inside the document).
      id: doc.id,
      name: d['name'] as String? ?? '',
      icon: d['icon'] as String?,
      image: d['image'] as String?,
      status: d['status'] as String? ?? 'active',
      restaurantCount: (d['restaurantCount'] as num? ?? 0).toInt(),
      sortOrder: (d['sortOrder'] as num? ?? 0).toInt(),
    );
  }
}
