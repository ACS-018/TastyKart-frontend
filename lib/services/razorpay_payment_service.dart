import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Result of a Checkout + server verification attempt.
class RazorpayCheckoutResult {
  final bool success;
  final bool verified;
  final String? reason;
  final String? razorpayPaymentId;

  const RazorpayCheckoutResult({
    required this.success,
    required this.verified,
    this.reason,
    this.razorpayPaymentId,
  });

  bool get isFullyVerified => success && verified;
}

/// Production Razorpay flow:
/// Flutter → createRazorpayOrder (CF) → Checkout → verifyRazorpayPayment (CF)
///
/// The Key Secret never lives in this app. Only the Key ID returned by
/// Cloud Functions is used to open Checkout.
class RazorpayPaymentService {
  RazorpayPaymentService() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  late final Razorpay _razorpay;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Completer<RazorpayCheckoutResult>? _pending;
  String? _firestoreOrderId;
  String? _customerName;
  String? _customerContact;
  String? _customerEmail;

  /// Creates a Razorpay order for an existing Firestore order, opens Checkout,
  /// then verifies payment server-side. Success UI must only show when
  /// [RazorpayCheckoutResult.isFullyVerified] is true.
  Future<RazorpayCheckoutResult> payForOrder({
    required String orderId,
    String? customerName,
    String? customerContact,
    String? customerEmail,
    String? preferredMethodLabel,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const RazorpayCheckoutResult(
        success: false,
        verified: false,
        reason: 'not_signed_in',
      );
    }

    if (_pending != null && !_pending!.isCompleted) {
      return const RazorpayCheckoutResult(
        success: false,
        verified: false,
        reason: 'payment_in_progress',
      );
    }

    _firestoreOrderId = orderId;
    _customerName = customerName ?? user.displayName;
    _customerContact = customerContact ?? user.phoneNumber;
    _customerEmail = customerEmail ?? user.email;
    _pending = Completer<RazorpayCheckoutResult>();

    try {
      final create = _functions.httpsCallable('createRazorpayOrder');
      final createResult = await create.call(<String, dynamic>{
        'orderId': orderId,
      });
      final data = Map<String, dynamic>.from(createResult.data as Map);

      final keyId = data['keyId'] as String?;
      final razorpayOrderId = data['razorpayOrderId'] as String?;
      final amount = data['amount'];
      final currency = data['currency'] as String? ?? 'INR';

      if (keyId == null ||
          keyId.isEmpty ||
          razorpayOrderId == null ||
          razorpayOrderId.isEmpty) {
        _complete(
          const RazorpayCheckoutResult(
            success: false,
            verified: false,
            reason: 'invalid_create_response',
          ),
        );
        return _pending!.future;
      }

      final options = <String, dynamic>{
        'key': keyId,
        'amount': amount,
        'currency': currency,
        'name': 'Tasty Kart',
        'description': 'Order $orderId',
        'order_id': razorpayOrderId,
        'prefill': <String, dynamic>{
          if (_customerName != null && _customerName!.isNotEmpty)
            'name': _customerName,
          if (_customerContact != null && _customerContact!.isNotEmpty)
            'contact': _customerContact,
          if (_customerEmail != null && _customerEmail!.isNotEmpty)
            'email': _customerEmail,
        },
        'notes': <String, dynamic>{
          'firestoreOrderId': orderId,
          if (preferredMethodLabel != null) 'preferred': preferredMethodLabel,
        },
        'theme': <String, dynamic>{'color': '#B32B2C'},
      };

      _razorpay.open(options);
      return _pending!.future;
    } on FirebaseFunctionsException catch (e) {
      _complete(
        RazorpayCheckoutResult(
          success: false,
          verified: false,
          reason: e.message ?? e.code,
        ),
      );
      return _pending!.future;
    } catch (e) {
      _complete(
        RazorpayCheckoutResult(
          success: false,
          verified: false,
          reason: e.toString(),
        ),
      );
      return _pending!.future;
    }
  }

  Future<void> _onSuccess(PaymentSuccessResponse response) async {
    final orderId = _firestoreOrderId;
    if (orderId == null) {
      _complete(
        const RazorpayCheckoutResult(
          success: false,
          verified: false,
          reason: 'missing_order',
        ),
      );
      return;
    }

    try {
      final verify = _functions.httpsCallable('verifyRazorpayPayment');
      final verifyResult = await verify.call(<String, dynamic>{
        'orderId': orderId,
        'razorpay_order_id': response.orderId,
        'razorpay_payment_id': response.paymentId,
        'razorpay_signature': response.signature,
      });
      final data = Map<String, dynamic>.from(verifyResult.data as Map);
      final success = data['success'] == true;
      final verified = data['verified'] == true;

      // CRITICAL: do not treat gateway success alone as paid.
      _complete(
        RazorpayCheckoutResult(
          success: success,
          verified: verified,
          reason: data['reason'] as String?,
          razorpayPaymentId: response.paymentId,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      _complete(
        RazorpayCheckoutResult(
          success: false,
          verified: false,
          reason: e.message ?? e.code,
          razorpayPaymentId: response.paymentId,
        ),
      );
    } catch (e) {
      // App may be killed after gateway success — webhook still reconciles.
      _complete(
        RazorpayCheckoutResult(
          success: false,
          verified: false,
          reason: 'verify_failed_webhook_will_reconcile',
          razorpayPaymentId: response.paymentId,
        ),
      );
    }
  }

  void _onError(PaymentFailureResponse response) {
    if (kDebugMode) {
      // Never log secrets; codes/messages only.
      debugPrint('Razorpay checkout error: ${response.code}');
    }
    _complete(
      RazorpayCheckoutResult(
        success: false,
        verified: false,
        reason: response.message ?? 'checkout_failed',
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // User selected an external wallet; wait for success/error callbacks.
    if (kDebugMode) {
      debugPrint('External wallet: ${response.walletName}');
    }
  }

  void _complete(RazorpayCheckoutResult result) {
    final c = _pending;
    if (c != null && !c.isCompleted) {
      c.complete(result);
    }
    _pending = null;
    _firestoreOrderId = null;
  }

  void dispose() {
    _razorpay.clear();
  }
}
