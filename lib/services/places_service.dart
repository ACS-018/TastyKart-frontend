import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/map_constants.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}

class PlaceDetails {
  final String formattedAddress;
  final double lat;
  final double lng;
  final String? name;

  const PlaceDetails({
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    this.name,
  });

  LatLng get latLng => LatLng(lat, lng);
}

/// Google Places Autocomplete + Details using the Maps API key.
class PlacesService {
  PlacesService._();

  static const _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  /// Search addresses/places (biased to India / Hyderabad region).
  static Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final q = input.trim();
    if (q.length < 2) return [];

    final uri = Uri.parse(_autocompleteUrl).replace(queryParameters: {
      'input': q,
      'key': MapConstants.googleMapKey,
      'components': 'country:in',
      'location': '${MapConstants.defaultCenter.latitude},'
          '${MapConstants.defaultCenter.longitude}',
      'radius': '80000',
      'types': 'geocode|establishment',
    });

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        return [];
      }

      final preds = data['predictions'] as List<dynamic>? ?? [];
      return preds.map((p) {
        final map = p as Map<String, dynamic>;
        final structured = map['structured_formatting'] as Map<String, dynamic>?;
        return PlaceSuggestion(
          placeId: map['place_id'] as String? ?? '',
          description: map['description'] as String? ?? '',
          mainText: structured?['main_text'] as String? ??
              map['description'] as String? ??
              '',
          secondaryText: structured?['secondary_text'] as String? ?? '',
        );
      }).where((s) => s.placeId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<PlaceDetails?> fetchDetails(String placeId) async {
    if (placeId.isEmpty) return null;

    final uri = Uri.parse(_detailsUrl).replace(queryParameters: {
      'place_id': placeId,
      'fields': 'formatted_address,geometry,name',
      'key': MapConstants.googleMapKey,
    });

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      return PlaceDetails(
        formattedAddress:
            result['formatted_address'] as String? ?? '',
        lat: (location['lat'] as num).toDouble(),
        lng: (location['lng'] as num).toDouble(),
        name: result['name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
