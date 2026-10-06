import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a saved payment card stored under
/// `customers/{uid}/savedCards/{cardId}`.
///
/// Only the masked card number (last 4 digits visible) is persisted —
/// real card credentials are never stored. Razorpay handles actual
/// card entry through its own secure checkout sheet.
class SavedCard {
  const SavedCard({
    required this.id,
    required this.maskedNumber,
    required this.cardHolder,
    required this.expiry,
    required this.savedAt,
    this.nickname,
  });

  /// Firestore document id (auto-generated).
  final String id;

  /// Masked card number shown to the user, e.g. "**** **** **** 4242".
  final String maskedNumber;

  /// Name on the card as entered by the user.
  final String cardHolder;

  /// Expiry in MM/YY format, e.g. "12/27".
  final String expiry;

  /// Optional label the user gave this card, e.g. "My HDFC Card".
  final String? nickname;

  /// When this card was saved (local time used as fallback if server
  /// timestamp has not resolved yet).
  final DateTime savedAt;

  // ── Display helpers ──────────────────────────────────────────────────────

  /// Returns the nickname if set, otherwise the masked number.
  String get displayName {
    final nick = nickname;
    return (nick != null && nick.isNotEmpty) ? nick : maskedNumber;
  }

  /// The last-four digits extracted from [maskedNumber].
  String get lastFour {
    final digits = maskedNumber.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  factory SavedCard.fromMap(String id, Map<String, dynamic> map) {
    DateTime savedAt;
    final raw = map['savedAt'];
    if (raw is Timestamp) {
      savedAt = raw.toDate();
    } else if (raw is String) {
      savedAt = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      savedAt = DateTime.now();
    }

    return SavedCard(
      id: id,
      maskedNumber: (map['maskedNumber'] as String?) ?? '•••• •••• •••• ????',
      cardHolder: (map['cardHolder'] as String?) ?? '',
      expiry: (map['expiry'] as String?) ?? '',
      nickname: map['nickname'] as String?,
      savedAt: savedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'maskedNumber': maskedNumber,
    'cardHolder': cardHolder,
    'expiry': expiry,
    if (nickname != null && nickname!.isNotEmpty) 'nickname': nickname!,
    'savedAt': savedAt.toIso8601String(),
  };

  SavedCard copyWith({
    String? id,
    String? maskedNumber,
    String? cardHolder,
    String? expiry,
    String? nickname,
    DateTime? savedAt,
  }) => SavedCard(
    id: id ?? this.id,
    maskedNumber: maskedNumber ?? this.maskedNumber,
    cardHolder: cardHolder ?? this.cardHolder,
    expiry: expiry ?? this.expiry,
    nickname: nickname ?? this.nickname,
    savedAt: savedAt ?? this.savedAt,
  );

  @override
  bool operator ==(Object other) => other is SavedCard && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
