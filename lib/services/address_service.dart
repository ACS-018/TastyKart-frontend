import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/delivery_address.dart';
import 'firestore_paths.dart';

/// User-scoped addresses: `customers/{uid}/addresses/{addressId}`.
class AddressService {
  AddressService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> _col(String uid) {
    return _db
        .collection(FirestorePaths.customers)
        .doc(uid)
        .collection('addresses');
  }

  static Stream<List<DeliveryAddress>> watchForUser(String uid) {
    return _col(uid).snapshots().map((snap) {
      final list = snap.docs
          .map(DeliveryAddress.fromDoc)
          .where((a) => a.isValid)
          .toList();
      // Default first, then label.
      list.sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
      return list;
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

    final existing = await _col(uid).get();
    final shouldDefault = makeDefault || existing.docs.isEmpty;

    if (shouldDefault) {
      await _clearDefaults(uid);
    }

    final ref = _col(uid).doc();
    final address = DeliveryAddress(
      id: ref.id,
      label: label,
      fullAddress: fullAddress,
      landmark: landmark,
      phone: phone,
      lat: lat,
      lng: lng,
      isDefault: shouldDefault,
    );

    await ref.set({
      ...address.toMap(),
      'userId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Mirror default onto customer doc for quick reads / Admin.
    if (shouldDefault) {
      await _mirrorDefault(uid, address);
    }

    return ref.id;
  }

  static Future<void> updateAddress(DeliveryAddress address) async {
    final uid = _uid;
    if (uid == null || address.id.isEmpty) {
      throw StateError('Invalid address update.');
    }
    await _col(uid).doc(address.id).set({
      ...address.toMap(),
      'userId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (address.isDefault) {
      await _clearDefaults(uid, exceptId: address.id);
      await _mirrorDefault(uid, address);
    }
  }

  static Future<void> deleteAddress(String addressId) async {
    final uid = _uid;
    if (uid == null || addressId.isEmpty) return;

    final doc = await _col(uid).doc(addressId).get();
    final wasDefault = doc.data()?['isDefault'] == true;
    await _col(uid).doc(addressId).delete();

    if (wasDefault) {
      final remaining = await _col(uid).limit(1).get();
      if (remaining.docs.isNotEmpty) {
        await setDefault(remaining.docs.first.id);
      } else {
        await _db.collection(FirestorePaths.customers).doc(uid).set({
          'defaultAddress': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  static Future<void> setDefault(String addressId) async {
    final uid = _uid;
    if (uid == null || addressId.isEmpty) return;

    await _clearDefaults(uid, exceptId: addressId);
    final ref = _col(uid).doc(addressId);
    await ref.set({
      'isDefault': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final snap = await ref.get();
    if (snap.exists) {
      await _mirrorDefault(uid, DeliveryAddress.fromDoc(snap));
    }
  }

  static Future<void> _clearDefaults(String uid, {String? exceptId}) async {
    final snap = await _col(uid).where('isDefault', isEqualTo: true).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      if (exceptId != null && d.id == exceptId) continue;
      batch.update(d.reference, {
        'isDefault': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Future<void> _mirrorDefault(
    String uid,
    DeliveryAddress address,
  ) async {
    await _db.collection(FirestorePaths.customers).doc(uid).set({
      'defaultAddress': address.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
