import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/map_constants.dart';

class GeocodingService {
  GeocodingService._();

  static Future<String?> reverseGeocode(LatLng point) async {
    // Platform geocoder first; Google Geocoding API as fallback (same map key).
    try {
      final places = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (places.isNotEmpty) {
        final formatted = _formatPlacemark(places.first);
        if (formatted.isNotEmpty) return formatted;
      }
    } catch (_) {}

    return _reverseGeocodeGoogle(point);
  }

  static Future<String?> _reverseGeocodeGoogle(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json',
      ).replace(queryParameters: {
        'latlng': '${point.latitude},${point.longitude}',
        'key': MapConstants.googleMapKey,
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      return (results.first as Map<String, dynamic>)['formatted_address']
          as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<LatLng?> geocodeAddress(String address) async {
    final q = address.trim();
    if (q.isEmpty) return null;
    try {
      final locations = await locationFromAddress(q);
      if (locations.isEmpty) return null;
      final loc = locations.first;
      return LatLng(loc.latitude, loc.longitude);
    } catch (_) {
      return null;
    }
  }

  static String _formatPlacemark(Placemark p) {
    final parts = <String>[
      if (p.subThoroughfare?.isNotEmpty == true) p.subThoroughfare!,
      if (p.thoroughfare?.isNotEmpty == true) p.thoroughfare!,
      if (p.subLocality?.isNotEmpty == true) p.subLocality!,
      if (p.locality?.isNotEmpty == true) p.locality!,
      if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
      if (p.postalCode?.isNotEmpty == true) p.postalCode!,
      if (p.country?.isNotEmpty == true) p.country!,
    ];
    return parts.join(', ');
  }
}
