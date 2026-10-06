import 'package:cloud_firestore/cloud_firestore.dart';

/// Saved delivery address for a signed-in customer.
/// Stored on Admin `customers/{userId}.addresses[]`.
class DeliveryAddress {
  final String id;
  final String label;
  final String fullAddress;
  final String? landmark;
  final String? phone;
  final double? lat;
  final double? lng;
  final bool isDefault;

  const DeliveryAddress({
    this.id = '',
    required this.label,
    required this.fullAddress,
    this.landmark,
    this.phone,
    this.lat,
    this.lng,
    this.isDefault = false,
  });

  bool get isValid => fullAddress.trim().isNotEmpty;

  DeliveryAddress copyWith({
    String? id,
    String? label,
    String? fullAddress,
    String? landmark,
    String? phone,
    double? lat,
    double? lng,
    bool? isDefault,
  }) {
    return DeliveryAddress(
      id: id ?? this.id,
      label: label ?? this.label,
      fullAddress: fullAddress ?? this.fullAddress,
      landmark: landmark ?? this.landmark,
      phone: phone ?? this.phone,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label.trim(),
      'fullAddress': fullAddress.trim(),
      if (landmark != null && landmark!.trim().isNotEmpty)
        'landmark': landmark!.trim(),
      if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'isDefault': isDefault,
    };
  }

  factory DeliveryAddress.fromMap(Map<String, dynamic> map) {
    return DeliveryAddress(
      id: (map['id'] as String? ?? '').trim(),
      label: (map['label'] as String? ?? 'Home').trim(),
      fullAddress: (map['fullAddress'] as String? ??
              map['address'] as String? ??
              '')
          .trim(),
      landmark: map['landmark'] as String?,
      phone: map['phone'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      isDefault: map['isDefault'] as bool? ?? false,
    );
  }

  factory DeliveryAddress.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final fromMap = DeliveryAddress.fromMap(Map<String, dynamic>.from(d));
    if (fromMap.id.isNotEmpty) return fromMap;
    return fromMap.copyWith(id: doc.id);
  }

  /// Prefer default address; otherwise first saved address.
  static DeliveryAddress? pickPreferred(List<DeliveryAddress> list) {
    if (list.isEmpty) return null;
    final defaults = list.where((a) => a.isDefault).toList();
    if (defaults.isNotEmpty) return defaults.first;
    return list.first;
  }
}
