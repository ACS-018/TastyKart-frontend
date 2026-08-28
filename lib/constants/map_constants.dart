import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google Maps SDK key — also configured in AndroidManifest / AppDelegate.
class MapConstants {
  MapConstants._();

  static const String googleMapKey = 'AIzaSyBwSjsnX7tDra6Wz5mw6wZRwRN57pi0NUM';

  /// Default map center (Hyderabad) when no saved coordinates exist.
  static const LatLng defaultCenter = LatLng(17.385044, 78.486671);

  static const double defaultZoom = 15;
  static const double trackingZoom = 13.5;
}
