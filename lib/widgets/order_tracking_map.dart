import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/color_constants.dart';
import '../constants/map_constants.dart';
import '../services/geocoding_service.dart';

/// Live Google Map for order tracking — restaurant → delivery address.
class OrderTrackingMap extends StatefulWidget {
  const OrderTrackingMap({
    super.key,
    this.destinationLat,
    this.destinationLng,
    this.destinationAddress,
    this.height = 280,
  });

  final double? destinationLat;
  final double? destinationLng;
  final String? destinationAddress;
  final double height;

  @override
  State<OrderTrackingMap> createState() => _OrderTrackingMapState();
}

class _OrderTrackingMapState extends State<OrderTrackingMap> {
  LatLng? _destination;
  LatLng? _origin;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolvePoints();
  }

  Future<void> _resolvePoints() async {
    LatLng? dest;
    if (widget.destinationLat != null && widget.destinationLng != null) {
      dest = LatLng(widget.destinationLat!, widget.destinationLng!);
    } else if (widget.destinationAddress?.trim().isNotEmpty == true) {
      dest = await GeocodingService.geocodeAddress(widget.destinationAddress!);
    }
    dest ??= MapConstants.defaultCenter;

    // Kitchen marker — slightly north-east of delivery (visual route).
    final origin = LatLng(
      dest.latitude + 0.012,
      dest.longitude + 0.008,
    );

    if (!mounted) return;
    setState(() {
      _destination = dest;
      _origin = origin;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _destination == null || _origin == null) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final dest = _destination!;
    final origin = _origin!;

    final markers = {
      Marker(
        markerId: const MarkerId('kitchen'),
        position: origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Kitchen', snippet: 'Preparing'),
      ),
      Marker(
        markerId: const MarkerId('home'),
        position: dest,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Delivery', snippet: 'Your address'),
      ),
    };

    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      points: [origin, dest],
      color: AppColors.primary,
      width: 4,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    );

    final bounds = LatLngBounds(
      southwest: LatLng(
        origin.latitude < dest.latitude ? origin.latitude : dest.latitude,
        origin.longitude < dest.longitude ? origin.longitude : dest.longitude,
      ),
      northeast: LatLng(
        origin.latitude > dest.latitude ? origin.latitude : dest.latitude,
        origin.longitude > dest.longitude ? origin.longitude : dest.longitude,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: widget.height,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: dest,
            zoom: MapConstants.trackingZoom,
          ),
          onMapCreated: (controller) {
            controller.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 56),
            );
          },
          markers: markers,
          polylines: {polyline},
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }
}
