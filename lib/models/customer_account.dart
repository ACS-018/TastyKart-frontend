import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin `customers/{id}` account fields used for block enforcement.
class CustomerAccount {
  final String id;
  final String status;
  final String? blockedAt;
  final String? blockedReason;
  final String email;
  final String phone;
  final String? uid;

  // ── Subscription fields ──────────────────────────────────────────────────
  final String? subscriptionPlanId;
  final String? subscriptionPlanName;

  /// 'active' | 'expired' | 'none'
  final String subscriptionStatus;

  /// UTC expiry — null when no subscription exists.
  final DateTime? subscribedUntil;

  const CustomerAccount({
    required this.id,
    required this.status,
    this.blockedAt,
    this.blockedReason,
    this.email = '',
    this.phone = '',
    this.uid,
    this.subscriptionPlanId,
    this.subscriptionPlanName,
    this.subscriptionStatus = 'none',
    this.subscribedUntil,
  });

  bool get isBlocked => status.toLowerCase().trim() == 'blocked';

  bool get isActive => !isBlocked;

  /// Returns true when the subscription is active AND not yet expired.
  bool get hasActiveSubscription {
    if (subscriptionStatus != 'active') return false;
    if (subscribedUntil == null) return false;
    return subscribedUntil!.isAfter(DateTime.now());
  }

  String get blockMessage {
    final reason = blockedReason?.trim();
    if (reason != null && reason.isNotEmpty) {
      return 'Your account has been blocked. Contact support.\nReason: $reason';
    }
    return 'Your account has been blocked. Contact support.';
  }

  factory CustomerAccount.fromMap(String id, Map<String, dynamic> map) {
    DateTime? subscribedUntil;
    final rawExpiry = map['subscribedUntil'];
    if (rawExpiry is Timestamp) {
      subscribedUntil = rawExpiry.toDate();
    } else if (rawExpiry is String && rawExpiry.isNotEmpty) {
      subscribedUntil = DateTime.tryParse(rawExpiry);
    }

    // Derive live status: if stored as 'active' but past expiry, treat as 'expired'.
    String subStatus = (map['subscriptionStatus'] as String? ?? 'none').trim();
    if (subStatus == 'active' &&
        subscribedUntil != null &&
        subscribedUntil.isBefore(DateTime.now())) {
      subStatus = 'expired';
    }

    return CustomerAccount(
      id: (map['id'] as String?)?.trim().isNotEmpty == true
          ? (map['id'] as String).trim()
          : id,
      status: (map['status'] as String? ?? 'active').trim(),
      blockedAt: map['blockedAt']?.toString(),
      blockedReason: map['blockedReason'] as String?,
      email: (map['email'] as String? ?? '').trim(),
      phone: (map['phone'] as String? ?? '').trim(),
      uid: (map['uid'] as String?)?.trim().isNotEmpty == true
          ? (map['uid'] as String).trim()
          : null,
      subscriptionPlanId: map['subscriptionPlanId'] as String?,
      subscriptionPlanName: map['subscriptionPlanName'] as String?,
      subscriptionStatus: subStatus,
      subscribedUntil: subscribedUntil,
    );
  }
}

/// Thrown when a signed-in user is blocked in Admin `customers`.
class CustomerBlockedException implements Exception {
  CustomerBlockedException(this.account);

  final CustomerAccount account;

  String get message => account.blockMessage;

  @override
  String toString() => message;
}
