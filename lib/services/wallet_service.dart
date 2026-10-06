import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_paths.dart';

/// Reads and writes the `walletBalance` field on `customers/{uid}`.
/// The balance is an integer in rupees (no paise).
class WalletService {
  WalletService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection(FirestorePaths.customers).doc(uid);

  /// Stream of the current wallet balance in ₹.
  static Stream<int> watchBalance(String uid) {
    return _ref(uid).snapshots().map(_extractBalance);
  }

  /// One-shot fetch of the current wallet balance in ₹.
  static Future<int> fetchBalance(String uid) async {
    final snap = await _ref(uid).get();
    return _extractBalance(snap);
  }

  /// Deducts [amount] from the wallet when an order is placed.
  /// Uses a transaction so the balance never goes below 0.
  /// Returns the actual amount deducted (may be less if balance was low).
  static Future<int> deduct({required String uid, required int amount}) async {
    if (amount <= 0) return 0;
    var deducted = 0;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_ref(uid));
      final current = _extractBalance(snap);
      deducted = amount.clamp(0, current);
      if (deducted <= 0) return;
      tx.set(_ref(uid), {
        'walletBalance': current - deducted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    return deducted;
  }

  /// Credits [amount] to the wallet — used for refunds.
  /// Runs inside a transaction so concurrent updates are safe.
  /// Returns the new balance after crediting.
  static Future<int> credit({required String uid, required int amount}) async {
    if (amount <= 0) return fetchBalance(uid);
    var newBalance = 0;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_ref(uid));
      final current = _extractBalance(snap);
      newBalance = current + amount;
      tx.set(_ref(uid), {
        'walletBalance': newBalance,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    return newBalance;
  }

  static int _extractBalance(DocumentSnapshot<Map<String, dynamic>> snap) {
    final raw = snap.data()?['walletBalance'];
    if (raw is num) return raw.toInt();
    return 0;
  }
}
