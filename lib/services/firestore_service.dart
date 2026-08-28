import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_paths.dart';

/// Customer-app Firestore helpers aligned with Admin schemas (`admin.md`).
///
/// Rules policy: this layer only **uses** existing collections. It never
/// deploys or alters Admin `firestore.rules` / `storage.rules`.
class FirestoreService {
  FirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Catalog streams ──────────────────────────────────────────────────────

  static Stream<QuerySnapshot> activeBanners() {
    return _db
        .collection(FirestorePaths.banners)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  static Stream<QuerySnapshot> activeFoodItems({bool availableOnly = false}) {
    Query<Map<String, dynamic>> q = _db
        .collection(FirestorePaths.foodItems)
        .where('status', isEqualTo: 'active');
    if (availableOnly) {
      q = q.where('available', isEqualTo: true);
    }
    return q.snapshots();
  }

  static Stream<QuerySnapshot> activeRestaurants() {
    return _db
        .collection(FirestorePaths.restaurants)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  static Stream<QuerySnapshot> activeRestaurantCategories() {
    return _db
        .collection(FirestorePaths.restaurantCategories)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  static Stream<QuerySnapshot> foodCategoriesForRestaurant(String restaurantId) {
    return _db
        .collection(FirestorePaths.foodCategories)
        .where('restaurantId', isEqualTo: restaurantId)
        .snapshots();
  }

  static Stream<QuerySnapshot> foodItemsForRestaurant(String restaurantId) {
    return _db
        .collection(FirestorePaths.foodItems)
        .where('restaurantId', isEqualTo: restaurantId)
        .snapshots();
  }

  static Stream<QuerySnapshot> addonsForRestaurant(String restaurantId) {
    return _db
        .collection(FirestorePaths.addons)
        .where('restaurantId', isEqualTo: restaurantId)
        .snapshots();
  }

  static Stream<DocumentSnapshot> restaurantById(String restaurantId) {
    return _db.collection(FirestorePaths.restaurants).doc(restaurantId).snapshots();
  }

  /// Fallback: match by name when older docs lack restaurantId.
  static Stream<QuerySnapshot> foodItemsByRestaurantName(String restaurantName) {
    return _db
        .collection(FirestorePaths.foodItems)
        .where('restaurantName', isEqualTo: restaurantName)
        .snapshots();
  }

  static Stream<QuerySnapshot> activeFoodCategories() {
    return _db
        .collection(FirestorePaths.foodCategories)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  static Stream<QuerySnapshot> activeAddons() {
    return _db
        .collection(FirestorePaths.addons)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  /// Fallback when addons docs omit `status`.
  static Stream<QuerySnapshot> allAddons() {
    return _db.collection(FirestorePaths.addons).snapshots();
  }

  static Stream<QuerySnapshot> notifications({int limit = 30}) {
    return _db
        .collection(FirestorePaths.notifications)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Soft fallback if `createdAt` index/orderBy fails — handled by callers.
  static Stream<QuerySnapshot> notificationsUnordered({int limit = 30}) {
    return _db.collection(FirestorePaths.notifications).limit(limit).snapshots();
  }

  static Stream<DocumentSnapshot> adminSettings() {
    return _db
        .collection(FirestorePaths.settings)
        .doc(FirestorePaths.settingsAdminDoc)
        .snapshots();
  }

  static Stream<QuerySnapshot> ordersByCustomer(String customerId) {
    return _db
        .collection(FirestorePaths.orders)
        .where('customerId', isEqualTo: customerId)
        .snapshots();
  }

  static Stream<QuerySnapshot> recentOrders({int limit = 20}) {
    return _db
        .collection(FirestorePaths.orders)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── Writes (compatible with current public Admin rules; no rule changes) ─

  /// Creates an order document matching Admin `orders` field keys.
  static Future<String> createOrder(Map<String, dynamic> data) async {
    final id = (data['id'] as String?)?.trim().isNotEmpty == true
        ? data['id'] as String
        : 'ORD-${DateTime.now().millisecondsSinceEpoch}';

    final payload = <String, dynamic>{
      ...data,
      'id': id,
      'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _db
        .collection(FirestorePaths.orders)
        .doc(id)
        .set(payload, SetOptions(merge: true));
    return id;
  }

  static Future<void> addReview(Map<String, dynamic> data) async {
    final id = (data['id'] as String?) ??
        'rev_${DateTime.now().millisecondsSinceEpoch}';
    await _db.collection(FirestorePaths.reviews).doc(id).set({
      ...data,
      'id': id,
      'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
