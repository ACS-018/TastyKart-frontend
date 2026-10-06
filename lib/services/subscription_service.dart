import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../constants/app_constants.dart';
import '../services/firestore_paths.dart';
import 'firestore_service.dart';

// ── Result ────────────────────────────────────────────────────────────────────

enum SubscriptionPaymentStatus {
  success,
  failed,
  cancelled,
  verificationPending,
}

class SubscriptionPaymentResult {
  const SubscriptionPaymentResult({
    required this.status,
    this.reason,
    this.razorpayPaymentId,
  });

  final SubscriptionPaymentStatus status;
  final String? reason;
  final String? razorpayPaymentId;

  bool get isSuccess => status == SubscriptionPaymentStatus.success;

  bool get isPending => status == SubscriptionPaymentStatus.verificationPending;
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Mirrors RazorpayPaymentService exactly:
///   1. Write a draft transaction doc to Firestore (like createOrder)
///   2. Call createRazorpayOrder CF with that doc id → get keyId
///   3. Open Razorpay Checkout
///   4. On success → call verifyRazorpayPayment CF
///   5. On verified → write subscription fields to customers/{uid}
class SubscriptionService {
  SubscriptionService() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  late final Razorpay _razorpay;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-south1',
  );
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Completer<SubscriptionPaymentResult>? _pending;

  String? _planId;
  String? _planName;
  int _planPrice = 0;
  String? _planDuration;
  String? _txId; // transaction / order doc id
  bool _cfOrderCreated = false; // true when CF returned a razorpayOrderId

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<SubscriptionPaymentResult> purchase({
    required String planId,
    required String planName,
    required int planPrice,
    required String planDuration,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SubscriptionPaymentResult(
        status: SubscriptionPaymentStatus.failed,
        reason: 'not_signed_in',
      );
    }

    if (_pending != null && !_pending!.isCompleted) {
      return const SubscriptionPaymentResult(
        status: SubscriptionPaymentStatus.failed,
        reason: 'payment_in_progress',
      );
    }

    _planId = planId;
    _planName = planName;
    _planPrice = planPrice;
    _planDuration = planDuration;
    _cfOrderCreated = false;
    _txId = 'SUB-${DateTime.now().millisecondsSinceEpoch}';
    _pending = Completer<SubscriptionPaymentResult>();

    // ── Step 1: Write a pending draft to orders collection ──────────────────
    // createRazorpayOrder CF reads from the `orders` collection by orderId.
    // We write a minimal draft here so the CF can find it and create the
    // Razorpay order with the correct amount.
    try {
      await _db.collection(FirestorePaths.orders).doc(_txId).set({
        'id': _txId,
        'type': 'subscription',
        'customerId': user.uid,
        'customerName': user.displayName ?? '',
        'customerEmail': user.email ?? '',
        'planId': planId,
        'planName': planName,
        'total': planPrice,
        'amount': planPrice,
        'currency': 'INR',
        'status': 'pending',
        'paymentMethod': 'Razorpay',
        'restaurantId': '',
        'restaurantName': '$planName Subscription',
        'items': <Map>[],
        'subtotal': planPrice,
        'tax': 0,
        'deliveryFee': 0,
        'platformFee': 0,
        'discount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionService: orders draft write failed: $e');
      }
      // Non-fatal — continue to CF
    }

    // ── Step 2: Call createRazorpayOrder CF (same as order payment) ──────────
    try {
      final create = _functions.httpsCallable('createRazorpayOrder');
      final result = await create.call(<String, dynamic>{
        'orderId': _txId, // CF uses this to look up amount / create Rzp order
      });
      final data = Map<String, dynamic>.from(result.data as Map);

      final keyId = data['keyId'] as String?;
      final razorpayOrderId = data['razorpayOrderId'] as String?;
      final amount = data['amount'];
      final currency = (data['currency'] as String?) ?? 'INR';

      if (keyId == null ||
          keyId.isEmpty ||
          razorpayOrderId == null ||
          razorpayOrderId.isEmpty) {
        const result = SubscriptionPaymentResult(
          status: SubscriptionPaymentStatus.failed,
          reason: 'invalid_cf_response',
        );
        _complete(result);
        return result;
      }

      _cfOrderCreated = true;

      // ── Step 3: Open Razorpay Checkout ──────────────────────────────────
      _razorpay.open(<String, dynamic>{
        'key': keyId,
        'amount': amount,
        'currency': currency,
        'name': AppConstants.appName,
        'description': '$planName Subscription',
        'order_id': razorpayOrderId,
        'prefill': <String, dynamic>{
          if ((user.displayName ?? '').isNotEmpty) 'name': user.displayName,
          if ((user.email ?? '').isNotEmpty) 'email': user.email,
          if ((user.phoneNumber ?? '').isNotEmpty) 'contact': user.phoneNumber,
        },
        'notes': <String, dynamic>{
          'planId': planId,
          'planName': planName,
          'transactionId': _txId,
        },
        'theme': <String, dynamic>{'color': '#B32B2C'},
      });
      // Razorpay is open — result arrives via _onSuccess / _onError callbacks.
      return _pending!.future;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionService CF error (${e.code}): ${e.message}');
      }
      final result = SubscriptionPaymentResult(
        status: SubscriptionPaymentStatus.failed,
        reason: e.message ?? e.code,
      );
      _complete(result);
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionService unexpected error: $e');
      }
      final result = SubscriptionPaymentResult(
        status: SubscriptionPaymentStatus.failed,
        reason: e.toString(),
      );
      _complete(result);
      return result;
    }
  }

  // ── Razorpay callbacks ──────────────────────────────────────────────────────

  Future<void> _onSuccess(PaymentSuccessResponse response) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _txId == null) {
      _complete(
        const SubscriptionPaymentResult(
          status: SubscriptionPaymentStatus.failed,
          reason: 'missing_context',
        ),
      );
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'SubscriptionService._onSuccess: '
        'paymentId=${response.paymentId} '
        'orderId=${response.orderId} '
        'cfOrderCreated=$_cfOrderCreated',
      );
    }

    // ── Step 4: Verify payment via CF (same as order payment) ────────────────
    if (_cfOrderCreated) {
      try {
        final verify = _functions.httpsCallable('verifyRazorpayPayment');
        final verifyResult = await verify.call(<String, dynamic>{
          'orderId': _txId,
          'razorpay_order_id': response.orderId ?? '',
          'razorpay_payment_id': response.paymentId ?? '',
          'razorpay_signature': response.signature ?? '',
        });
        final vData = Map<String, dynamic>.from(verifyResult.data as Map);
        final verified = vData['verified'] == true || vData['success'] == true;

        if (!verified) {
          if (kDebugMode) {
            debugPrint(
              'SubscriptionService: verify returned false. reason=${vData['reason']}',
            );
          }
          // Save optimistically — webhook will correct if something is wrong.
          await _saveAndComplete(
            uid: uid,
            paymentId: response.paymentId,
            status: SubscriptionPaymentStatus.verificationPending,
            reason: vData['reason'] as String? ?? 'not_verified',
          );
          return;
        }
      } on FirebaseFunctionsException catch (e) {
        if (kDebugMode) {
          debugPrint(
            'SubscriptionService: CF verify failed (${e.code}): ${e.message}',
          );
        }
        // CF verify unavailable — save subscription, webhook reconciles.
        await _saveAndComplete(
          uid: uid,
          paymentId: response.paymentId,
          status: SubscriptionPaymentStatus.verificationPending,
          reason: e.message ?? e.code,
        );
        return;
      } catch (e) {
        if (kDebugMode) debugPrint('SubscriptionService: verify exception: $e');
        await _saveAndComplete(
          uid: uid,
          paymentId: response.paymentId,
          status: SubscriptionPaymentStatus.verificationPending,
          reason: 'verify_exception',
        );
        return;
      }
    }

    // ── Step 5: Verified (or no CF order) — activate subscription ────────────
    await _saveAndComplete(
      uid: uid,
      paymentId: response.paymentId,
      status: SubscriptionPaymentStatus.success,
    );
  }

  void _onError(PaymentFailureResponse response) {
    if (kDebugMode) {
      debugPrint(
        'SubscriptionService checkout error: ${response.code} '
        '${response.message}',
      );
    }
    _complete(
      SubscriptionPaymentResult(
        status: response.code == Razorpay.PAYMENT_CANCELLED
            ? SubscriptionPaymentStatus.cancelled
            : SubscriptionPaymentStatus.failed,
        reason: response.message ?? 'checkout_error',
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (kDebugMode) debugPrint('External wallet: ${response.walletName}');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _saveAndComplete({
    required String uid,
    required String? paymentId,
    required SubscriptionPaymentStatus status,
    String? reason,
  }) async {
    try {
      final expiry = _expiryDate(_planDuration ?? 'monthly');
      await FirestoreService.saveSubscription(
        uid: uid,
        planId: _planId ?? '',
        planName: _planName ?? '',
        subscribedUntil: expiry,
        razorpayPaymentId: paymentId ?? '',
        amountPaid: _planPrice,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionService: Firestore save failed: $e');
      }
      _complete(
        SubscriptionPaymentResult(
          status: SubscriptionPaymentStatus.verificationPending,
          razorpayPaymentId: paymentId,
          reason: 'firestore_save_failed: $e',
        ),
      );
      return;
    }

    _complete(
      SubscriptionPaymentResult(
        status: status,
        razorpayPaymentId: paymentId,
        reason: reason,
      ),
    );
  }

  void _complete(SubscriptionPaymentResult result) {
    final c = _pending;
    if (c != null && !c.isCompleted) c.complete(result);
    _pending = null;
    _planId = null;
    _planName = null;
    _planPrice = 0;
    _planDuration = null;
    _txId = null;
    _cfOrderCreated = false;
  }

  static DateTime _expiryDate(String duration) {
    final now = DateTime.now();
    switch (duration.toLowerCase()) {
      case 'weekly':
        return now.add(const Duration(days: 7));
      case 'yearly':
        return DateTime(now.year + 1, now.month, now.day);
      case 'monthly':
      default:
        return DateTime(now.year, now.month + 1, now.day);
    }
  }

  void dispose() => _razorpay.clear();
}
