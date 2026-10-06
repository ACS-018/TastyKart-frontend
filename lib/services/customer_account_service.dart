import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/customer_account.dart';
import 'firestore_paths.dart';

/// Resolves Admin `customers` docs and enforces block status.
class CustomerAccountService {
  CustomerAccountService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection(FirestorePaths.customers);

  /// Prefer `customers/{auth.uid}`, else match by email/phone.
  static Future<CustomerAccount?> resolveForUser(User user) async {
    final byUid = await _customers.doc(user.uid).get();
    if (byUid.exists && byUid.data() != null) {
      return CustomerAccount.fromMap(byUid.id, byUid.data()!);
    }

    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      final byEmail = await _customers
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        final doc = byEmail.docs.first;
        return CustomerAccount.fromMap(doc.id, doc.data());
      }
      // Also try original casing if Admin stored mixed case.
      final byEmailRaw = await _customers
          .where('email', isEqualTo: user.email!.trim())
          .limit(1)
          .get();
      if (byEmailRaw.docs.isNotEmpty) {
        final doc = byEmailRaw.docs.first;
        return CustomerAccount.fromMap(doc.id, doc.data());
      }
    }

    final phone = user.phoneNumber?.trim();
    if (phone != null && phone.isNotEmpty) {
      final byPhone = await _customers
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (byPhone.docs.isNotEmpty) {
        final doc = byPhone.docs.first;
        return CustomerAccount.fromMap(doc.id, doc.data());
      }

      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        final last10 = digits.substring(digits.length - 10);
        final variants = <String>{
          phone,
          '+$digits',
          digits,
          last10,
          '+91$last10',
        };
        for (final variant in variants) {
          final snap = await _customers
              .where('phone', isEqualTo: variant)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final doc = snap.docs.first;
            return CustomerAccount.fromMap(doc.id, doc.data());
          }
        }
      }
    }

    return null;
  }

  /// Live updates for the resolved customer document (uid doc preferred).
  static Stream<CustomerAccount?> watchForUser(User user) async* {
    final resolved = await resolveForUser(user);
    final docId = resolved?.id ?? user.uid;
    yield* _customers.doc(docId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        // No profile yet — treat as active (signup / first sync).
        return null;
      }
      return CustomerAccount.fromMap(snap.id, snap.data()!);
    });
  }

  /// Fresh read for checkout / resume checks.
  static Future<CustomerAccount?> fetchLatestForUser(User user) {
    return resolveForUser(user);
  }

  /// Throws [CustomerBlockedException] if Admin marked the account blocked.
  /// Missing customer profile is allowed (handled by signup sync).
  static Future<CustomerAccount?> assertNotBlocked(User user) async {
    final account = await resolveForUser(user);
    if (account != null && account.isBlocked) {
      throw CustomerBlockedException(account);
    }
    return account;
  }

  static bool isBlockedAccount(CustomerAccount? account) =>
      account != null && account.isBlocked;
}
