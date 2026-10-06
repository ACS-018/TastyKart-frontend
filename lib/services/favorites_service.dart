import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/favorite_restaurant.dart';
import '../models/restaurant.dart';
import 'firestore_paths.dart';

/// User favourite stores — `customers/{uid}.favorites[]` (Admin schema).
class FavoritesService {
  FavoritesService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _customerRef(String uid) {
    return _db.collection(FirestorePaths.customers).doc(uid);
  }

  static Stream<List<FavoriteRestaurant>> watchForUser(String uid) {
    return _customerRef(uid).snapshots().map((snap) {
      return _parseFavoritesField(snap.data()?['favorites']);
    });
  }

  static Stream<List<FavoriteRestaurant>> watchCurrentUser() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return watchForUser(uid);
  }

  static Future<void> addRestaurant(Restaurant restaurant) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Sign in to save favourite restaurants.');
    }
    final restaurantId = _restaurantId(restaurant);
    if (restaurantId.isEmpty) return;

    final entry = FavoriteRestaurant.fromRestaurant(
      restaurant,
      restaurantId: restaurantId,
    );
    await _db.runTransaction((tx) async {
      final ref = _customerRef(uid);
      final snap = await tx.get(ref);
      final current = _parseFavoritesField(snap.data()?['favorites']);
      final without = current
          .where((f) => f.restaurantId != restaurantId)
          .map((f) => f.toMap())
          .toList();
      without.insert(0, entry.toMap());
      tx.set(
        ref,
        {
          'id': uid,
          'favorites': without,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> removeRestaurant(String restaurantId) async {
    final uid = _uid;
    if (uid == null || restaurantId.isEmpty) return;

    await _db.runTransaction((tx) async {
      final ref = _customerRef(uid);
      final snap = await tx.get(ref);
      final current = _parseFavoritesField(snap.data()?['favorites']);
      final next = current
          .where((f) => f.restaurantId != restaurantId)
          .map((f) => f.toMap())
          .toList();
      tx.set(
        ref,
        {
          'favorites': next,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> toggleRestaurant(Restaurant restaurant) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Sign in to save favourite restaurants.');
    }
    final restaurantId = _restaurantId(restaurant);
    if (restaurantId.isEmpty) return;

    final ref = _customerRef(uid);
    final snap = await ref.get();
    final current = _parseFavoritesField(snap.data()?['favorites']);
    final exists = current.any((f) => f.restaurantId == restaurantId);
    if (exists) {
      await removeRestaurant(restaurantId);
    } else {
      await addRestaurant(restaurant);
    }
  }

  static String _restaurantId(Restaurant restaurant) {
    return restaurant.id.trim();
  }

  static List<FavoriteRestaurant> _parseFavoritesField(dynamic raw) {
    if (raw == null) return const [];

    if (raw is Map) {
      return raw.entries
          .map((entry) {
            final value = entry.value;
            if (value is! Map) return null;
            final map = Map<String, dynamic>.from(value);
            map.putIfAbsent('restaurantId', () => entry.key.toString());
            return FavoriteRestaurant.fromMap(map);
          })
          .whereType<FavoriteRestaurant>()
          .where((f) => f.restaurantId.isNotEmpty)
          .toList();
    }

    if (raw is! List) return const [];

    final parsed = <FavoriteRestaurant>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      parsed.add(FavoriteRestaurant.fromMap(Map<String, dynamic>.from(entry)));
    }
    return parsed.where((f) => f.restaurantId.isNotEmpty).toList();
  }
}
