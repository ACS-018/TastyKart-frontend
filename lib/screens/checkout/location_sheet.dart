import 'package:flutter/material.dart';
import '../../models/delivery_address.dart';
import '../location/select_location_screen.dart';

/// Checkout helper — opens the Firebase-backed address picker.
class LocationSheet {
  LocationSheet._();

  static Future<DeliveryAddress?> show(BuildContext context) {
    return SelectLocationScreen.pick(context);
  }
}
