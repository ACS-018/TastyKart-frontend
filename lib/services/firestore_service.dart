import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/saved_card.dart';
import 'firestore_paths.dart';
import 'wallet_service.dart';

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

  static Stream<QuerySnapshot> foodCategoriesForRestaurant(
    String restaurantId,
  ) {
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

  /// Active offers for a restaurant — used by the user app to apply price
  /// overrides. Expiry is checked client-side.
  static Stream<QuerySnapshot> offersForRestaurant(String restaurantId) {
    return _db
        .collection('offers')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  static Stream<QuerySnapshot> addonsForRestaurant(String restaurantId) {
    return _db
        .collection(FirestorePaths.addons)
        .where('restaurantId', isEqualTo: restaurantId)
        .snapshots();
  }

  static Stream<DocumentSnapshot> restaurantById(String restaurantId) {
    return _db
        .collection(FirestorePaths.restaurants)
        .doc(restaurantId)
        .snapshots();
  }

  /// Fallback: match by name when older docs lack restaurantId.
  static Stream<QuerySnapshot> foodItemsByRestaurantName(
    String restaurantName,
  ) {
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
    return _db
        .collection(FirestorePaths.notifications)
        .limit(limit)
        .snapshots();
  }

  static Stream<QuerySnapshot> approvedSurgeRequests() {
    return _db
        .collection(FirestorePaths.surgeRequests)
        .where('status', isEqualTo: 'APPROVED')
        .snapshots();
  }

  static Stream<DocumentSnapshot> adminSettings() {
    return _db
        .collection(FirestorePaths.settings)
        .doc(FirestorePaths.settingsAdminDoc)
        .snapshots();
  }

  static Stream<QuerySnapshot> activeSubscriptions() {
    return _db
        .collection(FirestorePaths.subscriptions)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  /// Returns only non-expired, active subscription plans.
  /// Filters out:
  /// 1. Plans with status != 'active' (handled by activeSubscriptions query)
  /// 2. Plans where expiryDate is set and has passed
  static Stream<List<DocumentSnapshot>> activePlans() {
    return activeSubscriptions().map((snap) {
      final now = DateTime.now();
      return snap.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};

        // Double-check status is active (defensive)
        final status = data['status'] as String? ?? '';
        if (status != 'active') {
          return false;
        }

        // Check expiry date if present
        final expiry = data['expiryDate'] as String?;
        if (expiry == null || expiry.isEmpty) {
          return true; // no expiry = always valid
        }

        try {
          final expiryDate = DateTime.parse(expiry);
          // Only show if expiry date is in the future (after today)
          return expiryDate.isAfter(now);
        } catch (_) {
          return true; // unparseable date = don't filter out
        }
      }).toList();
    });
  }

  /// Live stream of a single customer doc (block status + subscription fields).
  static Stream<DocumentSnapshot> watchCustomerDoc(String uid) {
    return _db.collection(FirestorePaths.customers).doc(uid).snapshots();
  }

  /// Writes subscription fields onto customers/{uid} after a verified payment.
  /// Never overwrites block / identity fields.
  static Future<void> saveSubscription({
    required String uid,
    required String planId,
    required String planName,
    required DateTime subscribedUntil,
    required String razorpayPaymentId,
    required int amountPaid,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _db.collection(FirestorePaths.customers).doc(uid).set({
      'subscriptionPlanId': planId,
      'subscriptionPlanName': planName,
      'subscriptionStatus': 'active',
      'subscribedAt': now,
      'subscribedUntil': Timestamp.fromDate(subscribedUntil),
      'updatedAt': now,
    }, SetOptions(merge: true));

    // Record in transactions collection for admin visibility.
    final txId = 'TXN-${DateTime.now().millisecondsSinceEpoch}';
    await _db.collection(FirestorePaths.transactions).doc(txId).set({
      'id': txId,
      'type': 'subscription',
      'customerId': uid,
      'planId': planId,
      'planName': planName,
      'amount': amountPaid,
      'razorpayPaymentId': razorpayPaymentId,
      'status': 'paid',
      'subscribedUntil': Timestamp.fromDate(subscribedUntil),
      'createdAt': now,
    });
  }

  static Stream<QuerySnapshot> ordersByCustomer(String customerId) {
    return _db
        .collection(FirestorePaths.orders)
        .where('customerId', isEqualTo: customerId)
        .snapshots();
  }

  /// Watch a single order document by ID — for live tracking.
  static Stream<DocumentSnapshot> watchOrder(String orderId) {
    return _db.collection(FirestorePaths.orders).doc(orderId).snapshots();
  }

  // ── Order chat (orders/{id}/chat subcollection) ───────────────────────────

  /// Stream of chat messages for an order, newest last.
  static Stream<QuerySnapshot> watchOrderChat(String orderId) {
    return _db
        .collection(FirestorePaths.orders)
        .doc(orderId)
        .collection('chat')
        .orderBy('sentAt', descending: false)
        .snapshots();
  }

  /// Send a message in the order chat.
  /// [senderType] is 'customer' or 'partner'.
  static Future<void> sendChatMessage({
    required String orderId,
    required String senderId,
    required String senderName,
    required String senderType, // 'customer' | 'partner'
    required String message,
  }) async {
    final ref = _db
        .collection(FirestorePaths.orders)
        .doc(orderId)
        .collection('chat')
        .doc();
    await ref.set({
      'id': ref.id,
      'senderId': senderId,
      'senderName': senderName,
      'senderType': senderType,
      'message': message.trim(),
      'sentAt': FieldValue.serverTimestamp(),
      'read': false,
    });
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

  // ── Saved Cards ──────────────────────────────────────────────────────────

  /// Streams all saved cards for the given customer (ordered newest first).
  static Stream<List<SavedCard>> savedCardsStream(String uid) {
    return _db
        .collection(FirestorePaths.customers)
        .doc(uid)
        .collection(FirestorePaths.savedCards)
        .snapshots()
        .map((snap) {
          final cards = snap.docs
              .map((d) => SavedCard.fromMap(d.id, d.data()))
              .toList();
          // Sort client-side — avoids needing a Firestore composite index.
          cards.sort((a, b) => b.savedAt.compareTo(a.savedAt));
          return cards;
        });
  }

  /// Saves (or overwrites) a card document under customers/{uid}/savedCards.
  static Future<SavedCard> saveCard({
    required String uid,
    required String maskedNumber, // e.g. "**** **** **** 4242"
    required String cardHolder,
    required String expiry,
    required String? nickname,
  }) async {
    final ref = _db
        .collection(FirestorePaths.customers)
        .doc(uid)
        .collection(FirestorePaths.savedCards)
        .doc(); // auto-id

    final nick = nickname?.trim();
    final card = SavedCard(
      id: ref.id,
      maskedNumber: maskedNumber,
      cardHolder: cardHolder,
      expiry: expiry,
      nickname: (nick != null && nick.isNotEmpty) ? nick : null,
      savedAt: DateTime.now(),
    );

    await ref.set({...card.toMap(), 'savedAt': FieldValue.serverTimestamp()});
    return card;
  }

  /// Deletes a saved card by id.
  static Future<void> deleteSavedCard({
    required String uid,
    required String cardId,
  }) {
    return _db
        .collection(FirestorePaths.customers)
        .doc(uid)
        .collection(FirestorePaths.savedCards)
        .doc(cardId)
        .delete();
  }

  /// Updates the phone number on the customer document.
  static Future<void> updateCustomerPhone({
    required String uid,
    required String phone,
  }) {
    return _db.collection(FirestorePaths.customers).doc(uid).set({
      'phone': phone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes a pending order document — used to clean up when Razorpay
  /// payment is cancelled or fails after the order was pre-written to Firestore.
  static Future<void> deleteOrder(String orderId) {
    return _db.collection(FirestorePaths.orders).doc(orderId).delete();
  }

  /// Cancel an order on behalf of the customer (before the delivery partner
  /// picks up the food).
  ///
  /// Guards:
  ///  - Only allowed when [status] is pending / accepted / preparing.
  ///  - COD orders: sets [refundEligible]=false, [refundStatus]='not_applicable'.
  ///  - UPI / Razorpay / Wallet orders: sets [refundEligible]=true,
  ///    [refundStatus]='pending' — the admin panel shows a one-click refund
  ///    action for these orders.
  ///  - The assigned delivery partner is notified not to pick up the order;
  ///    their status is reset to online by the admin service layer.
  ///
  /// Returns [CancelOrderResult] with [success] flag and [refundEligible].
  static Future<CancelOrderResult> cancelOrderByUser({
    required String orderId,
    required String customerId,
    required String cancelReason,
  }) async {
    try {
      // 1. Fetch the live order document from the server.
      final snap = await _db
          .collection('orders')
          .doc(orderId)
          .get(const GetOptions(source: Source.server));
      if (!snap.exists) {
        return const CancelOrderResult(
          success: false,
          refundEligible: false,
          error: 'Order not found',
        );
      }

      final data = snap.data()!;

      // 2. Ownership guard.
      if ((data['customerId'] as String? ?? '') != customerId) {
        return const CancelOrderResult(
          success: false,
          refundEligible: false,
          error: 'Unauthorized',
        );
      }

      // 3. Pre-pickup status guard.
      final status = (data['status'] as String? ?? '').toLowerCase();
      const cancellable = {'pending', 'accepted', 'preparing'};
      if (!cancellable.contains(status)) {
        return CancelOrderResult(
          success: false,
          refundEligible: false,
          error: 'Order cannot be cancelled at status: $status',
        );
      }

      // 4. Determine refund eligibility by payment method.
      final paymentMethod = (data['paymentMethod'] as String? ?? '')
          .toLowerCase();
      final isCOD =
          paymentMethod.contains('cash') || paymentMethod.contains('cod');
      final refundEligible = !isCOD;

      final now = DateTime.now().toIso8601String();

      // 5. Build updated timeline (append cancellation entry).
      final rawTimeline = data['timeline'];
      final timeline = rawTimeline is List
          ? List<Map<String, dynamic>>.from(
              rawTimeline.map(
                (e) => e is Map<String, dynamic> ? e : <String, dynamic>{},
              ),
            )
          : <Map<String, dynamic>>[];
      timeline.add({'status': 'cancelled_by_user', 'time': now});

      // 6. Write the cancellation fields to Firestore.
      //    For COD+wallet orders, only walletUsed is auto-refunded immediately.
      //    Non-COD orders are left as 'pending' for admin to process manually.
      final walletUsed = (data['walletUsed'] as num? ?? 0).toInt();
      // Auto-refund only the wallet portion — only for COD+wallet cancelled by user.
      final autoRefundAmt = (isCOD && walletUsed > 0) ? walletUsed : 0;

      await _db.collection('orders').doc(orderId).update({
        'status': 'cancelled',
        'cancelledBy': 'user',
        'cancellationSource': 'user',
        'cancelReason': cancelReason,
        'userCancelledAt': now,
        'refundEligible': refundEligible,
        // COD+wallet: wallet portion auto-processed; non-COD: pending for admin
        'refundStatus': autoRefundAmt > 0
            ? 'processed'
            : (refundEligible ? 'pending' : 'not_applicable'),
        'walletRefunded': autoRefundAmt > 0,
        'timeline': timeline,
        // Clear delivery partner assignment on the order.
        'deliveryPartnerId': null,
        'deliveryPartnerName': null,
        'partnerAccepted': false,
        'deliveryStage': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Auto-credit wallet — only for COD+wallet (walletUsed amount only).
      // Non-COD refunds are handled manually by the admin.
      if (autoRefundAmt > 0) {
        try {
          await WalletService.credit(uid: customerId, amount: autoRefundAmt);
          // Record refundAmount on the order so admin panel shows it correctly.
          await _db.collection('orders').doc(orderId).update({
            'refundAmount': autoRefundAmt,
            'refundedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // Credit failed — revert refundStatus so admin can process manually.
          await _db
              .collection('orders')
              .doc(orderId)
              .update({'refundStatus': 'not_applicable'})
              .catchError((_) {});
        }
      }

      // 7. Notify the assigned delivery partner (if any) — "don't pick order".
      final partnerId = data['deliveryPartnerId'] as String? ?? '';
      final partnerName = data['deliveryPartnerName'] as String? ?? '';
      final orderNumber = data['orderNumber'] as String? ?? orderId;
      if (partnerId.isNotEmpty) {
        final notifRef = _db.collection('notifications').doc();
        await notifRef.set({
          'id': notifRef.id,
          'userId': partnerId,
          'userType': 'delivery_partner',
          'type': 'order_cancelled',
          'title': '❌ Order Cancelled by Customer',
          'message':
              'Order $orderNumber has been cancelled by the customer. '
              'Do NOT pick up this order. You are now available for new orders.',
          'data': {
            'orderId': orderId,
            'orderNumber': orderNumber,
            'action': 'order_cancelled_by_user',
            'cancelledBy': 'user',
          },
          'read': false,
          'priority': 'high',
          'createdAt': FieldValue.serverTimestamp(),
          // Also reset partner status to online so they receive new orders.
          // The admin service will reconcile; this notification triggers the
          // delivery app to flip itself back to online.
        });

        // Reset partner status directly from the user app as a best-effort
        // backup — the admin panel's reconciler also handles this.
        try {
          await _db.collection('deliveryPartners').doc(partnerId).update({
            'status': 'online',
            'currentOrder': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // Non-critical: admin panel reconciler will catch it.
        }
      }

      // 8. Admin-facing notification so the admin panel surfaces refund action.
      final adminNotifRef = _db.collection('notifications').doc();
      final autoRefunded = autoRefundAmt > 0;
      await adminNotifRef.set({
        'id': adminNotifRef.id,
        'userId': 'admin',
        'userType': 'admin',
        'type': 'order_cancelled',
        'title': autoRefunded
            ? '✅ Auto-Refunded — Order $orderNumber'
            : refundEligible
            ? '💳 Refund Pending — Order $orderNumber'
            : '🚫 Order Cancelled (COD) — $orderNumber',
        'message': autoRefunded
            ? 'Customer cancelled order $orderNumber. ₹$autoRefundAmt was automatically refunded to their wallet.'
            : refundEligible
            ? 'Customer cancelled order $orderNumber. '
                  'Payment was via ${data['paymentMethod']}. '
                  'Refund of ₹${data['total']} is pending.'
            : 'Customer cancelled order $orderNumber. '
                  'Payment was COD — no refund needed.',
        'orderId': orderId,
        'orderNumber': orderNumber,
        'data': {
          'orderId': orderId,
          'refundEligible': refundEligible,
          'autoRefunded': autoRefunded,
          'paymentMethod': data['paymentMethod'],
          'amount': data['total'],
          'action': autoRefunded ? 'view_order' : 'review_cancellation',
        },
        'read': false,
        'priority': autoRefunded ? 'medium' : 'high',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return CancelOrderResult(
        success: true,
        refundEligible: refundEligible,
        partnerWasAssigned: partnerId.isNotEmpty,
        partnerName: partnerName,
        paymentMethod: data['paymentMethod'] as String? ?? '',
        total: (data['total'] as num? ?? 0).toInt(),
        walletUsed: (data['walletUsed'] as num? ?? 0).toInt(),
      );
    } catch (e) {
      return CancelOrderResult(
        success: false,
        refundEligible: false,
        error: e.toString(),
      );
    }
  }

  /// After Razorpay payment is fully verified by the Cloud Function,
  /// updates the awaiting_payment placeholder order to confirmed status.
  /// This is the single write that makes the order "real" — visible to
  /// admin, restaurant, and delivery partners.
  static Future<void> updateOrderToVerified({
    required String orderId,
    required String paymentMethod,
    required String razorpayPaymentId,
  }) {
    return _db.collection(FirestorePaths.orders).doc(orderId).set({
      'paymentStatus': 'paid',
      'paymentVerified': true,
      'paymentMethod': paymentMethod,
      'razorpayPaymentId': razorpayPaymentId,
      // Flip status from 'pending' (awaiting payment) to 'pending' for
      // restaurant processing — already set in the placeholder; this
      // set with merge just adds the payment confirmation fields.
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks an order as payment_failed when Razorpay returns unverified.
  static Future<void> updateOrderPaymentFailed({
    required String orderId,
    required String reason,
  }) {
    return _db.collection(FirestorePaths.orders).doc(orderId).set({
      'paymentStatus': 'failed',
      'paymentVerified': false,
      'paymentFailureReason': reason.length > 200
          ? reason.substring(0, 200)
          : reason,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> addReview(Map<String, dynamic> data) async {
    final id =
        (data['id'] as String?) ??
        'rev_${DateTime.now().millisecondsSinceEpoch}';
    await _db.collection(FirestorePaths.reviews).doc(id).set({
      ...data,
      'id': id,
      'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Atomically increments a restaurant's [totalReviews] and recalculates its
  /// [averageRating] using a Firestore transaction.
  ///
  /// The restaurant doc is expected to have (or will be initialised with):
  ///   - `totalReviews`  : int
  ///   - `ratingSum`     : num  (running sum of all star values)
  ///   - `averageRating` : double (ratingSum / totalReviews, kept in sync)
  static Future<void> submitRestaurantRating({
    required String restaurantId,
    required int rating,
  }) async {
    if (restaurantId.isEmpty) return;

    final ref = _db.collection(FirestorePaths.restaurants).doc(restaurantId);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);

      final currentSum =
          (snap.exists ? (snap.data()?['ratingSum'] ?? 0) as num : 0)
              .toDouble();
      final currentTotal =
          (snap.exists ? (snap.data()?['totalReviews'] ?? 0) as num : 0)
              .toInt();

      final newTotal = currentTotal + 1;
      final newSum = currentSum + rating;
      final newAverage = double.parse((newSum / newTotal).toStringAsFixed(1));

      txn.set(ref, {
        // Dynamic fields — written on every new review submission.
        'ratingSum': newSum,
        'totalReviews': newTotal,
        'averageRating': newAverage,
        // Keep the legacy `rating` field in sync so the admin panel
        // (which reads `rating`) always shows the live user-driven score.
        'rating': newAverage,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}

/// Result returned by [FirestoreService.cancelOrderByUser].
class CancelOrderResult {
  const CancelOrderResult({
    required this.success,
    required this.refundEligible,
    this.partnerWasAssigned = false,
    this.partnerName = '',
    this.paymentMethod = '',
    this.total = 0,
    this.walletUsed = 0,
    this.error,
  });

  /// Whether the cancellation write succeeded.
  final bool success;

  /// True when the payment was online (UPI / Razorpay / Wallet) and a refund
  /// should be issued. False for Cash / COD orders.
  final bool refundEligible;

  /// True when a delivery partner was assigned (and has been notified).
  final bool partnerWasAssigned;

  /// Name of the delivery partner who was notified (for display purposes).
  final String partnerName;

  /// Original payment method string from the order document.
  final String paymentMethod;

  /// Order total in rupees — this is the post-wallet amount (what was charged
  /// online/cash). For COD+wallet orders total=cashPortion, walletUsed=walletPortion.
  final int total;

  /// Wallet credit that was applied to this order (may be > 0 even for COD).
  final int walletUsed;

  /// Non-null when [success] is false.
  final String? error;
}
