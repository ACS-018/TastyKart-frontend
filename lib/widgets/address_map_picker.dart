import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/color_constants.dart';
import '../constants/map_constants.dart';
import '../services/geocoding_service.dart';
import '../services/places_service.dart';
import 'address_search_field.dart';

/// Interactive map for picking a delivery pin when adding/editing an address.
class AddressMapPicker extends StatefulWidget {
  const AddressMapPicker({
    super.key,
    this.initialLat,
    this.initialLng,
    required this.onLocationChanged,
    this.onAddressResolved,
    this.height = 220,
    this.showSearch = true,
  });

  final double? initialLat;
  final double? initialLng;
  final ValueChanged<LatLng> onLocationChanged;
  final ValueChanged<String>? onAddressResolved;
  final double height;
  final bool showSearch;

  @override
  State<AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<AddressMapPicker> {
  GoogleMapController? _controller;
  late LatLng _pin;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _pin = _initialPoint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyLocation(_pin, resolveAddress: widget.onAddressResolved != null);
    });
  }

  LatLng _initialPoint() {
    if (widget.initialLat != null && widget.initialLng != null) {
      return LatLng(widget.initialLat!, widget.initialLng!);
    }
    return MapConstants.defaultCenter;
  }

  Future<void> _notifyLocation(LatLng point, {bool resolveAddress = true}) async {
    widget.onLocationChanged(point);
    if (!resolveAddress || widget.onAddressResolved == null) return;

    setState(() => _resolving = true);
    final text = await GeocodingService.reverseGeocode(point);
    if (!mounted) return;
    setState(() => _resolving = false);
    if (text != null && text.isNotEmpty) {
      widget.onAddressResolved!(text);
    }
  }

  Future<void> _applyPlace(PlaceDetails details) async {
    final point = details.latLng;
    setState(() => _pin = point);
    await applyPlaceToMap(
      controller: _controller,
      point: point,
      onLocationChanged: widget.onLocationChanged,
      onAddressResolved: widget.onAddressResolved,
      formattedAddress: details.formattedAddress,
    );
  }

  Future<void> _goToCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    final point = LatLng(pos.latitude, pos.longitude);
    setState(() => _pin = point);
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(point, MapConstants.defaultZoom),
    );
    await _notifyLocation(point);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSearch) ...[
          AddressSearchField(
            hintText: 'Search area, street, landmark…',
            onPlaceSelected: _applyPlace,
          ),
          const SizedBox(height: 10),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _pin,
                    zoom: MapConstants.defaultZoom,
                  ),
                  onMapCreated: (c) => _controller = c,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: {
                    Marker(
                      markerId: const MarkerId('delivery_pin'),
                      position: _pin,
                      draggable: true,
                      onDragEnd: (p) async {
                        setState(() => _pin = p);
                        await _notifyLocation(p);
                      },
                    ),
                  },
                  onTap: (p) async {
                    setState(() => _pin = p);
                    await _controller?.animateCamera(CameraUpdate.newLatLng(p));
                    await _notifyLocation(p);
                  },
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: FloatingActionButton.small(
                    heroTag: 'locate_me_${widget.hashCode}',
                    backgroundColor: AppColors.white,
                    onPressed: _goToCurrentLocation,
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_resolving)
                  const Positioned(
                    left: 10,
                    top: 10,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Finding address…',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Search above, tap the map, or drag the pin to set delivery location',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
