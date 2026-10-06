import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/delivery_address.dart';
import 'firestore_paths.dart';

/// User addresses on Admin `customers/{uid}.addresses[]`
/// (same pattern as `favorites` — works with customer-doc rules).
class AddressService {
  AddressService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _customerRef(String uid) {
    return _db.collection(FirestorePaths.customers).doc(uid);
  }

  static Stream<List<DeliveryAddress>> watchForUser(String uid) {
    return _customerRef(uid).snapshots().map((snap) {
      return _parseList(snap.data()?['addresses']);
    });
  }

  static Stream<List<DeliveryAddress>> watchCurrentUser() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return watchForUser(uid);
  }

  static Future<String> addAddress({
    required String label,
    required String fullAddress,
    String? landmark,
    String? phone,
    double? lat,
    double? lng,
    bool makeDefault = false,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Sign in required to save an address.');
    }

    final id = 'addr_${DateTime.now().millisecondsSinceEpoch}';

    await _db.runTransaction((tx) async {
      final ref = _customerRef(uid);
      final snap = await tx.get(ref);
      final current = _parseList(snap.data()?['addresses']);
      final shouldDefault = makeDefault || current.isEmpty;

      final next = current
          .map(
            (a) => a.copyWith(isDefault: shouldDefault ? false : a.isDefault),
          )
          .toList();

      final saved = DeliveryAddress(
        id: id,
        label: label,
        fullAddress: fullAddress,
        landmark: landmark,
        phone: phone,
        lat: lat,
        lng: lng,
        isDefault: shouldDefault,
      );
      next.insert(0, saved);

      tx.set(
        ref,
        {
          'id': uid,
          'addresses': next.map((a) => a.toMap()).toList(),
          if (shouldDefault) 'defaultAddress': saved.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    return id;
  }

  static Future<void> updateAddress(DeliveryAddress address) async {
    final uid = _uid;
    if (uid == null || address.id.isEmpty) {
      throw StateError('Invalid address update.');
    }

    await _db.runTransaction((tx) async {
      final ref = _customerRef(uid);
      final snap = await tx.get(ref);
      var current = _parseList(snap.data()?['addresses']);
      final index = current.indexWhere((a) => a.id == address.id);
      if (index < 0) {
        throw StateError('Address not found.');
      }

      var updated = address;
      if (address.isDefault) {
        current = current
            .map((a) => a.copyWith(isDefault: a.id == address.id))
            .toList();
        updated = address.copyWith(isDefault: true);
      }

      current[index] = updated;

      tx.set(
        ref,
        {
          'addresses': current.map((a) => a.toMap()).toList(),
          if (updated.isDefault) 'defaultAddress': updated.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> deleteAddress(String addressId) async {
    final uid = _uid;
    if (uid == null || addressId.isEmpty) return;

    await _db.runTransaction((tx) async {
      final ref = _customerRef(uid);
      final snap = await tx.get(ref);
      final current = _parseList(snap.data()?['addresses']);
      final removed = current.where((a) => a.id == addressId).toList();
      if (removed.isEmpty) return;

      final wasDefault = removed.first.isDefault;
      var next = current.where((a) => a.id != addressId).toList();

      DeliveryAddress? newDefault;
      if (wasDefault && next.isNotEmpty) {
        newDefault = next.first.copyWith(isDefault: true);
        next = [
          newDefault,
          ...next.skip(1).map((a) => a.copyWith(isDefault: false)),
        ];
      }

      final payload = <String, dynamic>{
        'addresses': next.map((a) => a.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (newDefault != null) {
        payload['defaultAddress'] = newDefault.toMap();
      } else if (wasDefault) {
        payload['defaultAddress'] = FieldValue.delete();
      }

      tx.set(ref, payload, SetOptions(merge: true));
    });
  }

  static Future<void> setDefault(String addressId) async {
    final uid = _uid;
    if (uid == null || addressId.isEmpty) return;

    await _db.runTransaction((tx) async {
      final ref = _customerRef(uid);
      final snap = await tx.get(ref);
      final current = _parseList(snap.data()?['addresses']);
      if (!current.any((a) => a.id == addressId)) return;

      final next = current
          .map((a) => a.copyWith(isDefault: a.id == addressId))
          .toList();
      final def = next.firstWhere((a) => a.id == addressId);

      tx.set(
        ref,
        {
          'addresses': next.map((a) => a.toMap()).toList(),
          'defaultAddress': def.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static List<DeliveryAddress> _parseList(dynamic raw) {
    if (raw is! List) return const [];
    final list = raw
        .whereType<Map>()
        .map((e) => DeliveryAddress.fromMap(Map<String, dynamic>.from(e)))
        .where((a) => a.isValid)
        .toList();
    list.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return list;
  }
}
