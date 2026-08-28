import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/color_constants.dart';
import '../services/geocoding_service.dart';
import '../services/places_service.dart';

/// Google Places autocomplete search field.
class AddressSearchField extends StatefulWidget {
  const AddressSearchField({
    super.key,
    this.hintText = 'Search area, street, landmark…',
    this.initialValue,
    this.onPlaceSelected,
    this.onTextSubmitted,
  });

  final String hintText;
  final String? initialValue;
  final void Function(PlaceDetails details)? onPlaceSelected;
  final void Function(String query)? onTextSubmitted;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (value.trim().length < 2) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _loading = false;
            _showSuggestions = false;
          });
        }
        return;
      }

      if (mounted) setState(() => _loading = true);
      final results = await PlacesService.autocomplete(value);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
        _showSuggestions = _focus.hasFocus && results.isNotEmpty;
      });
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion item) async {
    setState(() {
      _showSuggestions = false;
      _loading = true;
      _controller.text = item.description;
    });
    _focus.unfocus();

    final details = await PlacesService.fetchDetails(item.placeId);
    if (!mounted) return;
    setState(() => _loading = false);

    if (details != null) {
      widget.onPlaceSelected?.call(details);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load place details. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submitText() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    widget.onTextSubmitted?.call(q);

    setState(() => _loading = true);
    final point = await GeocodingService.geocodeAddress(q);
    if (!mounted) return;
    setState(() => _loading = false);

    if (point != null) {
      widget.onPlaceSelected?.call(
        PlaceDetails(
          formattedAddress: q,
          lat: point.latitude,
          lng: point.longitude,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No location found for that search'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: (v) {
            setState(() => _showSuggestions = true);
            _onChanged(v);
          },
          onTap: () => setState(() => _showSuggestions = _suggestions.isNotEmpty),
          onSubmitted: (_) => _submitText(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: _submitText,
                    color: AppColors.primary,
                  ),
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_showSuggestions && _suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  title: Text(
                    s.mainText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: s.secondaryText.isEmpty
                      ? null
                      : Text(
                          s.secondaryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                  onTap: () => _selectSuggestion(s),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Helper to move map pin from search result.
Future<void> applyPlaceToMap({
  required GoogleMapController? controller,
  required LatLng point,
  required ValueChanged<LatLng> onLocationChanged,
  ValueChanged<String>? onAddressResolved,
  String? formattedAddress,
}) async {
  onLocationChanged(point);
  await controller?.animateCamera(
    CameraUpdate.newLatLngZoom(point, 16),
  );
  if (onAddressResolved != null) {
    if (formattedAddress != null && formattedAddress.isNotEmpty) {
      onAddressResolved(formattedAddress);
    } else {
      final text = await GeocodingService.reverseGeocode(point);
      if (text != null && text.isNotEmpty) onAddressResolved(text);
    }
  }
}
