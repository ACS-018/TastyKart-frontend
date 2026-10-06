import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../constants/color_constants.dart';
import '../../services/address_service.dart';
import '../../services/geocoding_service.dart';
import '../../state/cart_controller.dart';
import '../../widgets/address_map_picker.dart';
import '../../widgets/address_search_field.dart';
import '../../widgets/app_screen_header.dart';
import '../../services/places_service.dart';

class SelectLocationScreen extends StatefulWidget {
  const SelectLocationScreen({super.key, this.manageOnly = false});

  /// When true, selecting does not pop with a result (Settings manage flow).
  final bool manageOnly;

  static Future<DeliveryAddress?> pick(BuildContext context) {
    return Navigator.push<DeliveryAddress>(
      context,
      MaterialPageRoute(builder: (_) => const SelectLocationScreen()),
    );
  }

  @override
  State<SelectLocationScreen> createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends State<SelectLocationScreen> {
  String _savedFilter = '';
  bool _locating = false;
  // Holds the last resolved address string so we can show it as subtitle.
  String? _resolvedAddress;

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Location permission denied'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      final address = await GeocodingService.reverseGeocode(latLng);
      final fullAddress = address ?? '${pos.latitude}, ${pos.longitude}';

      // Show the resolved address as subtitle immediately.
      if (mounted) setState(() => _resolvedAddress = fullAddress);

      if (!mounted) return;

      final current = DeliveryAddress(
        id: 'current_location',
        label: 'Current Location',
        fullAddress: fullAddress,
        lat: pos.latitude,
        lng: pos.longitude,
      );

      // Directly select the address — no add-form sheet needed.
      CartScope.of(context).setAddress(current);
      if (!widget.manageOnly) {
        Navigator.pop(context, current);
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Using your current location'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not get your location. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openAddForm({DeliveryAddress? existing}) async {
    final saved = await showModalBottomSheet<DeliveryAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddAddressSheet(existing: existing),
    );
    if (saved == null || !mounted) return;

    CartScope.of(context).setAddress(saved);
    if (!widget.manageOnly) {
      Navigator.pop(context, saved);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${saved.label}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _openAddFromPlace(PlaceDetails details) {
    _openAddForm(
      existing: DeliveryAddress(
        id: '',
        label: details.name?.trim().isNotEmpty == true
            ? details.name!.trim()
            : 'Home',
        fullAddress: details.formattedAddress,
        lat: details.lat,
        lng: details.lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          _RedHeader(
            title: 'Select Location',
            subtitle: 'Saved addresses for your account',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: uid == null
                ? const Center(
                    child: Text('Please sign in to manage addresses'),
                  )
                : StreamBuilder<List<DeliveryAddress>>(
                    stream: AddressService.watchForUser(uid),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final all = snapshot.data ?? const <DeliveryAddress>[];
                      final q = _savedFilter.trim().toLowerCase();
                      final addresses = q.isEmpty
                          ? all
                          : all
                                .where(
                                  (a) =>
                                      a.label.toLowerCase().contains(q) ||
                                      a.fullAddress.toLowerCase().contains(q),
                                )
                                .toList();

                      return SafeArea(
                        top: false,
                        bottom: true,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                            children: [
                              const Text(
                                'Select Your Location',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 14),
                              AddressSearchField(
                                hintText: 'Search area, street, landmark…',
                                onPlaceSelected: _openAddFromPlace,
                                onTextSubmitted: (v) =>
                                    setState(() => _savedFilter = v),
                              ),
                              const SizedBox(height: 16),
                              const Padding(
                                padding: EdgeInsets.only(left: 2, bottom: 8),
                                child: Text(
                                  'Use Current Address',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6B6B6B),
                                  ),
                                ),
                              ),
                              // ── Use current location ───────────────
                              Material(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _locating ? null : _useCurrentLocation,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.1,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: _locating
                                              ? const Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.my_location_rounded,
                                                  color: AppColors.primary,
                                                  size: 20,
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Use Current Location',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                _resolvedAddress ??
                                                    'Detect your location automatically',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF6B6B6B),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Color(0xFF6B6B6B),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Padding(
                                padding: EdgeInsets.only(left: 2, bottom: 8),
                                child: Text(
                                  'Add Or Manage Addresses',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6B6B6B),
                                  ),
                                ),
                              ),
                              _ArrowTile(
                                title: 'Add Address',
                                subtitle: 'Save a new delivery location',
                                onTap: () => _openAddForm(),
                              ),
                              const SizedBox(height: 8),
                              const _DashedLabel(text: 'Saved Address'),
                              const SizedBox(height: 8),
                              if (addresses.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'No saved addresses yet',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF6B6B6B),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () => _openAddForm(),
                                        icon: const Icon(
                                          Icons.add_location_alt,
                                        ),
                                        label: const Text(
                                          'Add your first address',
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...addresses.map((address) {
                                  return _AddressCard(
                                    address: address,
                                    onTap: () {
                                      CartScope.of(context).setAddress(address);
                                      if (!widget.manageOnly) {
                                        Navigator.pop(context, address);
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Selected ${address.label}',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                    onSetDefault: address.isDefault
                                        ? null
                                        : () async {
                                            await AddressService.setDefault(
                                              address.id,
                                            );
                                          },
                                    onEdit: () =>
                                        _openAddForm(existing: address),
                                    onDelete: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete address?'),
                                          content: Text(
                                            'Remove "${address.label}" from your account?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        await AddressService.deleteAddress(
                                          address.id,
                                        );
                                      }
                                    },
                                  );
                                }),
                            ], // ListView.children
                          ), // ListView
                        ), // Container
                      ); // SafeArea (return)
                    }, // builder
                  ), // StreamBuilder
          ), // Expanded
        ],
      ),
    );
  }
}

/// Bottom sheet to create / edit a Firestore address for the signed-in user.
class AddAddressSheet extends StatefulWidget {
  const AddAddressSheet({super.key, this.existing});

  final DeliveryAddress? existing;

  @override
  State<AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<AddAddressSheet> {
  late final TextEditingController _label;
  late final TextEditingController _full;
  late final TextEditingController _landmark;
  late final TextEditingController _phone;
  late bool _makeDefault;
  bool _saving = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? 'Home');
    _full = TextEditingController(text: e?.fullAddress ?? '');
    _landmark = TextEditingController(text: e?.landmark ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _makeDefault = e?.isDefault ?? true;
    _lat = e?.lat;
    _lng = e?.lng;
  }

  @override
  void dispose() {
    _label.dispose();
    _full.dispose();
    _landmark.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _fillAddressFromPin(String text) {
    if (text.trim().isEmpty) return;
    // Don't overwrite a pre-filled address when editing an existing one.
    if (_full.text.trim().isNotEmpty) return;
    setState(() {
      _full.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final full = _full.text.trim();
    if (label.isEmpty || full.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Label and full address are required'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      // Only treat as an update when we have a real saved id.
      // A DeliveryAddress with id='' means it was pre-filled from a place
      // search (new address, not yet in Firestore) — always use addAddress.
      if (existing != null && existing.id.isNotEmpty) {
        final updated = existing.copyWith(
          label: label,
          fullAddress: full,
          landmark: _landmark.text.trim().isEmpty
              ? null
              : _landmark.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          isDefault: _makeDefault,
          lat: _lat,
          lng: _lng,
        );
        await AddressService.updateAddress(updated);
        if (mounted) {
          Navigator.pop(context, updated.copyWith(isDefault: _makeDefault));
        }
      } else {
        // New address (blank form or pre-filled from place/GPS search).
        final landmark = _landmark.text.trim().isEmpty
            ? null
            : _landmark.text.trim();
        final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
        final id = await AddressService.addAddress(
          label: label,
          fullAddress: full,
          landmark: landmark,
          phone: phone,
          lat: _lat,
          lng: _lng,
          makeDefault: _makeDefault,
        );
        final saved = DeliveryAddress(
          id: id,
          label: label,
          fullAddress: full,
          landmark: landmark,
          phone: phone,
          lat: _lat,
          lng: _lng,
          isDefault: _makeDefault,
        );
        if (mounted) Navigator.pop(context, saved);
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().contains('permission-denied')
          ? 'Permission denied. Please sign in again and try.'
          : e.toString().contains('Sign in required')
          ? 'Please sign in to save an address.'
          : 'Could not save address. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing == null || widget.existing!.id.isEmpty
                    ? 'Add Address'
                    : 'Edit Address',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              AddressMapPicker(
                initialLat: _lat,
                initialLng: _lng,
                onLocationChanged: (LatLng p) {
                  _lat = p.latitude;
                  _lng = p.longitude;
                },
                onAddressResolved: _fillAddressFromPin,
                // Resolve on init only when editing an existing saved address
                // (has a real id). For new addresses — including those
                // pre-filled from a place search — skip init geocoding so
                // the user's pre-filled address text isn't overwritten.
                resolveOnInit:
                    widget.existing != null && widget.existing!.id.isNotEmpty,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _full,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Full address',
                  hintText: 'Filled automatically from map pin',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (Home, Work, …)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _landmark,
                decoration: const InputDecoration(
                  labelText: 'Landmark (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Set as default address',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                value: _makeDefault,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _makeDefault = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          'Save Address',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowTile extends StatelessWidget {
  const _ArrowTile({required this.title, this.subtitle, required this.onTap});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
            ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onTap,
    this.onSetDefault,
    this.onEdit,
    this.onDelete,
  });

  final DeliveryAddress address;
  final VoidCallback onTap;
  final VoidCallback? onSetDefault;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: address.isDefault
                ? AppColors.primary.withValues(alpha: 0.45)
                : const Color(0xFFEEEEEE),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    address.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (address.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Default',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              address.fullAddress,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B6B6B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onSetDefault != null)
                  TextButton(
                    onPressed: onSetDefault,
                    child: const Text('Make default'),
                  ),
                if (onEdit != null)
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                if (onDelete != null)
                  TextButton(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLabel extends StatelessWidget {
  const _DashedLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFCCCCCC))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B6B6B),
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFCCCCCC))),
      ],
    );
  }
}

class _RedHeader extends StatelessWidget {
  const _RedHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AppScreenHeader(title: title, subtitle: subtitle, onBack: onBack);
  }
}
