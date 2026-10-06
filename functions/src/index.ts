import * as crypto from "crypto";
import {initializeApp} from "firebase-admin/app";
import {getMessaging} from "firebase-admin/messaging";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type Transaction,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import Razorpay = require("razorpay");

initializeApp();
const db = getFirestore();

/** Production secrets — set via `firebase functions:secrets:set` (never in source). */
const RAZORPAY_KEY_ID = defineSecret("RAZORPAY_KEY_ID");
const RAZORPAY_KEY_SECRET = defineSecret("RAZORPAY_KEY_SECRET");
const RAZORPAY_WEBHOOK_SECRET = defineSecret("RAZORPAY_WEBHOOK_SECRET");

const CURRENCY = "INR";

type OrderDoc = DocumentData;

function requireAuth(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function toPaise(amountRupees: number): number {
  if (!Number.isFinite(amountRupees) || amountRupees <= 0) {
    throw new HttpsError("failed-precondition", "Invalid order amount.");
  }
  return Math.round(amountRupees * 100);
}

function razorpayClient(keyId: string, keySecret: string): Razorpay {
  return new Razorpay({key_id: keyId, key_secret: keySecret});
}

function computePayablePaise(order: OrderDoc): number {
  const total = Number(order.total ?? 0);
  const items = Array.isArray(order.items) ? order.items : [];
  let itemsSum = 0;
  for (const it of items) {
    const price = Number(it?.price ?? 0);
    const qty = Number(it?.qty ?? 1);
    itemsSum += price * qty;
  }
  const tax = Number(order.tax ?? 0);
  const deliveryFee = Number(order.deliveryFee ?? 0);  // already includes surgeFee
  const platformFee = Number(order.platformFee ?? 0);
  const discount = Number(order.discount ?? 0);
  const tip = Number(order.tip ?? 0);              // customer tip (optional)
  const walletUsed = Number(order.walletUsed ?? 0); // wallet credit deducted from total

  // Mirror the Flutter grandTotal formula:
  //   itemsTotal + deliveryFee + tax + platformFee - discount + tip - walletUsed
  const recomputed = itemsSum + tax + deliveryFee + platformFee - discount + tip - walletUsed;

  if (total <= 0) {
    throw new HttpsError("failed-precondition", "Order has no payable total.");
  }
  if (items.length > 0 && Math.abs(recomputed - total) > 1) {
    logger.warn("Order amount mismatch vs line items", {
      orderId: order.id,
      total,
      recomputed,
      itemsSum,
      tax,
      deliveryFee,
      platformFee,
      discount,
      tip,
      walletUsed,
    });
    throw new HttpsError(
      "failed-precondition",
      "Order amount failed server validation."
    );
  }
  return toPaise(total);
}

function hmacSha256Hex(payload: string, secret: string): string {
  return crypto.createHmac("sha256", secret).update(payload).digest("hex");
}

function timingSafeEqualHex(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a, "utf8");
    const bb = Buffer.from(b, "utf8");
    if (ba.length !== bb.length) return false;
    return crypto.timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}

async function markPaymentProcessedIdempotent(
  paymentId: string,
  payload: Record<string, unknown>
): Promise<boolean> {
  const ref = db.collection("paymentEvents").doc(paymentId);
  try {
    await db.runTransaction(async (tx: Transaction) => {
      const snap = await tx.get(ref);
      if (snap.exists && snap.data()?.processed === true) {
        throw new Error("ALREADY_PROCESSED");
      }
      tx.set(
        ref,
        {
          ...payload,
          processed: true,
          processedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    });
    return true;
  } catch (e) {
    if (e instanceof Error && e.message === "ALREADY_PROCESSED") {
      return false;
    }
    throw e;
  }
}

/**
 * Resolves the order data from either `pendingPayments` or `orders`.
 * Returns { ref, data, isPending } where isPending=true means the doc
 * lives in pendingPayments and must be promoted to orders on success.
 */
async function resolveOrderDoc(firestoreOrderId: string): Promise<{
  ref: FirebaseFirestore.DocumentReference;
  data: OrderDoc;
  isPending: boolean;
}> {
  const pendingRef = db.collection("pendingPayments").doc(firestoreOrderId);
  const pendingSnap = await pendingRef.get();
  if (pendingSnap.exists) {
    return {ref: pendingRef, data: pendingSnap.data() as OrderDoc, isPending: true};
  }
  const orderRef = db.collection("orders").doc(firestoreOrderId);
  const orderSnap = await orderRef.get();
  if (orderSnap.exists) {
    return {ref: orderRef, data: orderSnap.data() as OrderDoc, isPending: false};
  }
  throw new HttpsError("not-found", "Order not found.");
}

/**
 * Promotes a pendingPayments doc into orders and deletes the pending doc.
 * If it's already in orders (legacy or COD), just updates it.
 */
async function applyPaidUpdate(params: {
  firestoreOrderId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  amountPaise: number;
  currency: string;
  source: "verify" | "webhook";
}): Promise<void> {
  const {ref: sourceRef, data, isPending} = await resolveOrderDoc(params.firestoreOrderId);

  // Idempotency: already paid
  if (data.paymentVerified === true && data.paymentStatus === "paid") return;

  if (
    data.razorpayOrderId &&
    data.razorpayOrderId !== params.razorpayOrderId
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay order ID does not match this order."
    );
  }
  const expectedPaise = computePayablePaise(data);
  if (params.amountPaise !== expectedPaise) {
    throw new HttpsError("failed-precondition", "Payment amount mismatch.");
  }
  if ((params.currency || "").toUpperCase() !== CURRENCY) {
    throw new HttpsError("failed-precondition", "Currency mismatch.");
  }

  const paymentFields = {
    paymentStatus: "paid",
    paymentVerified: true,
    razorpayOrderId: params.razorpayOrderId,
    razorpayPaymentId: params.razorpayPaymentId,
    paidAmount: params.amountPaise / 100,
    paidAmountPaise: params.amountPaise,
    currency: CURRENCY,
    paymentVerifiedAt: FieldValue.serverTimestamp(),
    paymentSource: params.source,
    updatedAt: FieldValue.serverTimestamp(),
    timeline: FieldValue.arrayUnion({
      status: "payment_paid",
      time: new Date().toISOString(),
      source: params.source,
    }),
  };

  if (isPending) {
    // Promote: write the full doc to orders, then delete the pending doc.
    const orderRef = db.collection("orders").doc(params.firestoreOrderId);
    const promotedDoc = {
      ...data,
      ...paymentFields,
      // Remove placeholder flags before promoting
      isPlaceholder: FieldValue.delete(),
    };
    await orderRef.set(promotedDoc, {merge: false});
    await sourceRef.delete();
    logger.info("Promoted pendingPayments → orders", {
      orderId: params.firestoreOrderId,
      source: params.source,
    });
  } else {
    // Already in orders collection — just update it.
    await sourceRef.update(paymentFields);
  }
}

async function applyFailedUpdate(
  firestoreOrderId: string,
  reason: string
): Promise<void> {
  // On failure, just update whichever collection holds the doc.
  // pendingPayments docs stay pending — they'll be cleaned up by the user
  // cancelling or by a TTL purge. We don't promote them to orders.
  const pendingRef = db.collection("pendingPayments").doc(firestoreOrderId);
  const pendingSnap = await pendingRef.get();
  const ref = pendingSnap.exists
    ? pendingRef
    : db.collection("orders").doc(firestoreOrderId);

  await ref.set(
    {
      paymentStatus: "failed",
      paymentVerified: false,
      paymentFailureReason: reason.slice(0, 200),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
}

async function applyRefundUpdate(
  firestoreOrderId: string,
  refundId: string,
  status: string
): Promise<void> {
  const orderRef = db.collection("orders").doc(firestoreOrderId);
  await orderRef.set(
    {
      paymentStatus: status === "processed" ? "refunded" : "refund_pending",
      refundId,
      refundStatus: status,
      updatedAt: FieldValue.serverTimestamp(),
      timeline: FieldValue.arrayUnion({
        status: status === "processed" ? "refunded" : "refund_created",
        time: new Date().toISOString(),
        refundId,
      }),
    },
    {merge: true}
  );
}

/**
 * createRazorpayOrder
 * Input: { orderId: string } — Firestore pendingPayments (or orders) doc id.
 * Amount is always read/validated from Firestore (never from client).
 * Placeholder is written to `pendingPayments`, NOT `orders`, so the admin
 * panel never sees unverified payment orders.
 */
export const createRazorpayOrder = onCall(
  {
    region: "asia-south1",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const orderId = String(request.data?.orderId ?? "").trim();
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId is required.");
    }

    // Look in pendingPayments first, then fall back to orders (legacy COD/wallet
    // orders that somehow end up here, or re-payment attempts).
    const {ref: orderRef, data: order} = await resolveOrderDoc(orderId);

    if (order.customerId && order.customerId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "You do not own this order."
      );
    }

    if (order.paymentVerified === true && order.paymentStatus === "paid") {
      throw new HttpsError(
        "failed-precondition",
        "Order is already paid."
      );
    }

    const amountPaise = computePayablePaise(order);
    const keyId = RAZORPAY_KEY_ID.value();
    const keySecret = RAZORPAY_KEY_SECRET.value();
    const rzp = razorpayClient(keyId, keySecret);

    if (
      order.razorpayOrderId &&
      typeof order.razorpayOrderId === "string" &&
      order.paymentStatus !== "paid"
    ) {
      try {
        const existing = await rzp.orders.fetch(order.razorpayOrderId);
        const existingAmount = Number(existing.amount);
        if (
          existingAmount === amountPaise &&
          String(existing.currency).toUpperCase() === CURRENCY &&
          existing.status !== "paid"
        ) {
          await orderRef.set(
            {
              paymentStatus: "awaiting_payment",
              paymentVerified: false,
              currency: CURRENCY,
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true}
          );
          return {
            keyId,
            razorpayOrderId: order.razorpayOrderId,
            amount: amountPaise,
            currency: CURRENCY,
            orderId,
          };
        }
      } catch {
        logger.warn("Existing Razorpay order fetch failed; creating new", {
          orderId,
        });
      }
    }

    let rzOrder: {id: string; amount: number | string; currency: string};
    try {
      rzOrder = await rzp.orders.create({
        amount: amountPaise,
        currency: CURRENCY,
        receipt: orderId.slice(0, 40),
        notes: {
          firestoreOrderId: orderId,
          customerId: uid,
        },
      });
    } catch {
      logger.error("Razorpay order create failed", {orderId});
      throw new HttpsError(
        "unavailable",
        "Unable to create payment order. Try again."
      );
    }

    await orderRef.set(
      {
        razorpayOrderId: rzOrder.id,
        paymentStatus: "awaiting_payment",
        paymentVerified: false,
        currency: CURRENCY,
        payableAmountPaise: amountPaise,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      keyId,
      razorpayOrderId: rzOrder.id,
      amount: amountPaise,
      currency: CURRENCY,
      orderId,
    };
  }
);

/**
 * verifyRazorpayPayment
 * Verifies HMAC signature + Razorpay payment entity, then marks order paid.
 */
export const verifyRazorpayPayment = onCall(
  {
    region: "asia-south1",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const firestoreOrderId = String(request.data?.orderId ?? "").trim();
    const razorpayOrderId = String(
      request.data?.razorpay_order_id ?? ""
    ).trim();
    const razorpayPaymentId = String(
      request.data?.razorpay_payment_id ?? ""
    ).trim();
    const razorpaySignature = String(
      request.data?.razorpay_signature ?? ""
    ).trim();

    if (
      !firestoreOrderId ||
      !razorpayOrderId ||
      !razorpayPaymentId ||
      !razorpaySignature
    ) {
      throw new HttpsError("invalid-argument", "Missing payment fields.");
    }

    const {data: order} = await resolveOrderDoc(firestoreOrderId);

    if (order.customerId && order.customerId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "You do not own this order."
      );
    }

    if (
      order.paymentVerified === true &&
      order.paymentStatus === "paid" &&
      order.razorpayPaymentId === razorpayPaymentId
    ) {
      return {success: true, verified: true, alreadyProcessed: true};
    }

    if (order.razorpayOrderId && order.razorpayOrderId !== razorpayOrderId) {
      return {success: false, verified: false, reason: "wrong_order_id"};
    }

    const keySecret = RAZORPAY_KEY_SECRET.value();
    const expected = hmacSha256Hex(
      `${razorpayOrderId}|${razorpayPaymentId}`,
      keySecret
    );
    if (!timingSafeEqualHex(expected, razorpaySignature)) {
      logger.warn("Invalid Razorpay signature", {firestoreOrderId});
      return {success: false, verified: false, reason: "invalid_signature"};
    }

    await markPaymentProcessedIdempotent(razorpayPaymentId, {
      firestoreOrderId,
      razorpayOrderId,
      source: "verify",
      uid,
    });

    const keyId = RAZORPAY_KEY_ID.value();
    const rzp = razorpayClient(keyId, keySecret);

    let payment: {
      id: string;
      order_id: string;
      amount: number | string;
      currency: string;
      status: string;
    };
    try {
      payment = await rzp.payments.fetch(razorpayPaymentId);
    } catch {
      logger.error("Razorpay payment fetch failed", {firestoreOrderId});
      throw new HttpsError(
        "unavailable",
        "Unable to verify payment with gateway."
      );
    }

    if (payment.id !== razorpayPaymentId) {
      return {success: false, verified: false, reason: "payment_id_mismatch"};
    }
    if (payment.order_id !== razorpayOrderId) {
      return {success: false, verified: false, reason: "order_id_mismatch"};
    }

    const amountPaise = Number(payment.amount);
    const currency = String(payment.currency || "").toUpperCase();
    const status = String(payment.status || "").toLowerCase();

    if (!["authorized", "captured"].includes(status)) {
      await applyFailedUpdate(firestoreOrderId, `status_${status}`);
      return {success: false, verified: false, reason: "payment_not_captured"};
    }

    try {
      await applyPaidUpdate({
        firestoreOrderId,
        razorpayOrderId,
        razorpayPaymentId,
        amountPaise,
        currency,
        source: "verify",
      });
    } catch (err) {
      const message =
        err instanceof HttpsError ? err.message : "verification_failed";
      logger.warn("applyPaidUpdate failed", {firestoreOrderId, message});
      return {success: false, verified: false, reason: message};
    }

    return {success: true, verified: true};
  }
);

/**
 * razorpayWebhook — recovers payments when the app is killed after Checkout.
 */
export const razorpayWebhook = onRequest(
  {
    region: "asia-south1",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const signature = String(req.get("x-razorpay-signature") || "");
    const webhookSecret = RAZORPAY_WEBHOOK_SECRET.value();
    const rawBody =
      typeof req.rawBody !== "undefined"
        ? req.rawBody.toString("utf8")
        : JSON.stringify(req.body);

    const expected = hmacSha256Hex(rawBody, webhookSecret);
    if (!signature || !timingSafeEqualHex(expected, signature)) {
      logger.warn("Webhook signature verification failed");
      res.status(400).send("Invalid signature");
      return;
    }

    const event = req.body?.event as string | undefined;
    const payload = req.body?.payload;
    const eventId =
      (req.body?.id as string | undefined) ||
      `${event}_${payload?.payment?.entity?.id || payload?.refund?.entity?.id || Date.now()}`;

    const eventRef = db.collection("webhookEvents").doc(eventId);
    const eventSnap = await eventRef.get();
    if (eventSnap.exists && eventSnap.data()?.processed === true) {
      res.status(200).json({ok: true, duplicate: true});
      return;
    }

    try {
      switch (event) {
        case "payment.authorized":
        case "payment.captured": {
          const payment = payload?.payment?.entity;
          if (!payment?.id) break;
          const razorpayPaymentId = String(payment.id);
          const razorpayOrderId = String(payment.order_id || "");
          const amountPaise = Number(payment.amount);
          const currency = String(payment.currency || "").toUpperCase();
          const notes = payment.notes || {};
          let firestoreOrderId = String(notes.firestoreOrderId || "");

          if (!firestoreOrderId && razorpayOrderId) {
            // Check pendingPayments first, then orders
            const pq = await db
              .collection("pendingPayments")
              .where("razorpayOrderId", "==", razorpayOrderId)
              .limit(1)
              .get();
            if (!pq.empty) {
              firestoreOrderId = pq.docs[0].id;
            } else {
              const q = await db
                .collection("orders")
                .where("razorpayOrderId", "==", razorpayOrderId)
                .limit(1)
                .get();
              if (!q.empty) {
                firestoreOrderId = q.docs[0].id;
              }
            }
          }

          if (!firestoreOrderId) {
            logger.warn("Webhook payment without Firestore order mapping");
            break;
          }

          const should = await markPaymentProcessedIdempotent(
            razorpayPaymentId,
            {
              firestoreOrderId,
              razorpayOrderId,
              source: "webhook",
              event,
            }
          );
          if (should) {
            await applyPaidUpdate({
              firestoreOrderId,
              razorpayOrderId,
              razorpayPaymentId,
              amountPaise,
              currency,
              source: "webhook",
            });
          } else {
            // Event claimed earlier — still ensure order is paid (race with verify).
            const pendingSnap2 = await db
              .collection("pendingPayments")
              .doc(firestoreOrderId)
              .get();
            const reconcileSnap = pendingSnap2.exists
              ? pendingSnap2
              : await db.collection("orders").doc(firestoreOrderId).get();
            if (
              reconcileSnap.exists &&
              reconcileSnap.data()?.paymentVerified !== true
            ) {
              await applyPaidUpdate({
                firestoreOrderId,
                razorpayOrderId,
                razorpayPaymentId,
                amountPaise,
                currency,
                source: "webhook",
              });
            }
          }
          break;
        }
        case "payment.failed": {
          const payment = payload?.payment?.entity;
          const notes = payment?.notes || {};
          let firestoreOrderId = String(notes.firestoreOrderId || "");
          const razorpayOrderId = String(payment?.order_id || "");
          if (!firestoreOrderId && razorpayOrderId) {
            const pq = await db
              .collection("pendingPayments")
              .where("razorpayOrderId", "==", razorpayOrderId)
              .limit(1)
              .get();
            if (!pq.empty) {
              firestoreOrderId = pq.docs[0].id;
            } else {
              const q = await db
                .collection("orders")
                .where("razorpayOrderId", "==", razorpayOrderId)
                .limit(1)
                .get();
              if (!q.empty) firestoreOrderId = q.docs[0].id;
            }
          }
          if (firestoreOrderId) {
            await applyFailedUpdate(
              firestoreOrderId,
              String(payment?.error_description || "payment_failed")
            );
          }
          break;
        }
        case "refund.created":
        case "refund.processed": {
          const refund = payload?.refund?.entity;
          const payment = payload?.payment?.entity;
          const refundId = String(refund?.id || "");
          const razorpayPaymentId = String(
            refund?.payment_id || payment?.id || ""
          );
          let firestoreOrderId = "";
          if (razorpayPaymentId) {
            const q = await db
              .collection("orders")
              .where("razorpayPaymentId", "==", razorpayPaymentId)
              .limit(1)
              .get();
            if (!q.empty) firestoreOrderId = q.docs[0].id;
          }
          if (firestoreOrderId && refundId) {
            await applyRefundUpdate(
              firestoreOrderId,
              refundId,
              event === "refund.processed" ? "processed" : "created"
            );
          }
          break;
        }
        default:
          logger.info("Unhandled webhook event", {event});
      }

      await eventRef.set(
        {
          event,
          processed: true,
          processedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      res.status(200).json({ok: true});
    } catch (err) {
      logger.error("Webhook processing error", {
        event,
        message: err instanceof Error ? err.message : "unknown",
      });
      res.status(500).json({ok: false});
    }
  }
);

/**
 * sendCustomerNotification
 *
 * Triggered whenever a document is created in the `notifications` collection.
 * The delivery-boy app writes docs here (via OrderService.notifyCustomer) for
 * events like `order_delayed` and `order_transferred`.  This function reads the
 * target customer's FCM tokens from `customers/{userId}.fcmTokens[]` and sends
 * a push notification to every registered device.
 *
 * Document shape expected:
 *   userId      string   — customer uid
 *   userType    string   — must be 'customer' (guards against admin/partner docs)
 *   type        string   — e.g. 'order_delayed' | 'order_transferred'
 *   title       string   — notification title
 *   message     string   — notification body
 *   orderId     string   — Firestore order doc id
 *   orderNumber string   — human-readable order number
 *   data        object   — extra key-value pairs forwarded as FCM data payload
 *   read        boolean  — false on creation; updated to true after send
 */
export const sendCustomerNotification = onDocumentCreated(
  {
    document: "notifications/{notifId}",
    region: "asia-south1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const notif = snap.data();

    // Only handle customer-targeted notifications.
    if (!notif || notif.userType !== "customer") return;

    const userId: string = notif.userId ?? "";
    const title: string = notif.title ?? "TastyKart";
    const body: string = notif.message ?? "";
    const orderId: string = notif.orderId ?? "";
    const orderNumber: string = notif.orderNumber ?? "";
    const type: string = notif.type ?? "";
    const extraData: Record<string, string> = {};

    // Flatten the nested `data` map into string key-value pairs for FCM.
    const rawData = notif.data as Record<string, unknown> | undefined;
    if (rawData) {
      for (const [k, v] of Object.entries(rawData)) {
        if (v !== undefined && v !== null) {
          extraData[k] = String(v);
        }
      }
    }

    if (!userId) {
      logger.warn("sendCustomerNotification: missing userId", {
        notifId: snap.id,
      });
      return;
    }

    // Fetch FCM tokens from customers/{userId}.fcmTokens[].
    const customerRef = db.collection("customers").doc(userId);
    const customerSnap = await customerRef.get();
    if (!customerSnap.exists) {
      logger.warn("sendCustomerNotification: customer doc not found", {
        userId,
      });
      return;
    }

    const customerData = customerSnap.data()!;

    // Respect the notificationsEnabled flag written by the app.
    // Tokens are no longer deleted on toggle-off; this flag is the gate.
    const notificationsEnabled = customerData.notificationsEnabled !== false;
    if (!notificationsEnabled) {
      logger.info("sendCustomerNotification: notifications disabled for user", {
        userId,
      });
      return;
    }

    const tokens: string[] = Array.isArray(customerData.fcmTokens)
      ? (customerData.fcmTokens as string[]).filter(
          (t) => typeof t === "string" && t.trim().length > 0
        )
      : [];

    if (tokens.length === 0) {
      logger.info("sendCustomerNotification: no FCM tokens for user", {
        userId,
      });
      return;
    }

    const messaging = getMessaging();

    // Send to all registered tokens in a single MulticastMessage call.
    const messagePayload = {
      tokens,
      notification: {title, body},
      data: {
        orderId,
        orderNumber,
        type,
        ...extraData,
      },
      android: {
        notification: {
          channelId: "tasty_kart_general",
          priority: "high" as const,
          sound: "default",
        },
        priority: "high" as const,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await messaging.sendEachForMulticast(messagePayload);
      logger.info("sendCustomerNotification: FCM sent", {
        userId,
        type,
        orderId,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });

      // Clean up stale tokens that returned a registration-not-found error.
      const staleTokens: string[] = [];
      response.responses.forEach((resp, idx) => {
        if (
          !resp.success &&
          (resp.error?.code ===
            "messaging/registration-token-not-registered" ||
            resp.error?.code === "messaging/invalid-registration-token")
        ) {
          staleTokens.push(tokens[idx]);
        }
      });

      if (staleTokens.length > 0) {
        await customerRef.update({
          fcmTokens: FieldValue.arrayRemove(...staleTokens),
          updatedAt: FieldValue.serverTimestamp(),
        });
        logger.info("sendCustomerNotification: removed stale tokens", {
          userId,
          count: staleTokens.length,
        });
      }
    } catch (err) {
      logger.error("sendCustomerNotification: FCM send failed", {
        userId,
        orderId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);

/**
 * notifyCustomerOnOrderCancelled
 *
 * Triggered whenever an order document is updated.  Handles two cases:
 *
 * 1. status → 'cancelled'
 *    Writes a notification doc so `sendCustomerNotification` pushes an FCM
 *    message telling the user their order was cancelled.
 *
 * 2. refundAmount field added (order stays 'cancelled')
 *    The admin called `refundToWallet()` which increments the customer's
 *    walletBalance and sets refundAmount on the order without changing status.
 *    This trigger writes a wallet_refund notification so the user gets an FCM
 *    push confirming the refund, even with the app in background/terminated.
 */
export const notifyCustomerOnOrderCancelled = onDocumentUpdated(
  {
    document: "orders/{orderId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const prevStatus = String(before.status ?? "").toLowerCase().trim();
    const newStatus = String(after.status ?? "").toLowerCase().trim();

    const orderId = event.params.orderId;
    const customerId: string = String(after.customerId ?? "").trim();
    const orderNumber: string = String(
      after.orderNumber ?? after.id ?? orderId
    ).trim();
    const restaurantName: string = String(after.restaurantName ?? "").trim();
    const displayNum = orderNumber.startsWith("#")
      ? orderNumber
      : `#${orderNumber}`;

    if (!customerId) {
      logger.warn("notifyCustomerOnOrderCancelled: no customerId", {orderId});
      return;
    }

    // ── Branch 1: order just became 'cancelled' ────────────────────────────
    if (newStatus === "cancelled" && prevStatus !== "cancelled") {
      const cancelledBy: string = String(
        after.cancelledBy ?? ""
      ).toLowerCase();
      const isPartnerCancel = cancelledBy === "delivery_partner";

      const title = "Order Cancelled ❌";
      const body = isPartnerCancel
        ? `Your order ${displayNum}${
            restaurantName ? ` from ${restaurantName}` : ""
          } was cancelled by the delivery partner. If you were charged, a refund will be processed shortly.`
        : `Your order ${displayNum}${
            restaurantName ? ` from ${restaurantName}` : ""
          } has been cancelled. If you were charged, a refund will be processed shortly.`;

      try {
        await db.collection("notifications").add({
          userId: customerId,
          userType: "customer",
          type: "order_cancelled",
          title,
          message: body,
          orderId,
          orderNumber,
          data: {orderId, orderNumber, action: "view_order"},
          read: false,
          priority: "high",
          createdAt: FieldValue.serverTimestamp(),
          expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        });
        logger.info("notifyCustomerOnOrderCancelled: cancellation notif written", {
          orderId,
          customerId,
          cancelledBy: cancelledBy || "admin",
        });
      } catch (err) {
        logger.error("notifyCustomerOnOrderCancelled: cancellation write failed", {
          orderId,
          error: err instanceof Error ? err.message : String(err),
        });
      }
      return;
    }

    // ── Branch 2: refundAmount was just added to a cancelled order ──────────
    // Status stays 'cancelled' — refundToWallet() no longer changes status.
    // Detect the refund by checking if refundAmount just appeared or increased.
    const prevRefund = Number(before.refundAmount ?? 0);
    const newRefund = Number(after.refundAmount ?? 0);

    if (newStatus === "cancelled" && newRefund > 0 && newRefund !== prevRefund) {
      const title = "💰 Refund credited to your wallet!";
      const body =
        `₹${newRefund} has been added to your TastyKart wallet for order ${displayNum}.`;

      try {
        await db.collection("notifications").add({
          userId: customerId,
          userType: "customer",
          type: "wallet_refund",
          title,
          message: body,
          orderId,
          orderNumber,
          data: {
            orderId,
            orderNumber,
            amount: String(newRefund),
            action: "view_wallet",
          },
          read: false,
          priority: "high",
          createdAt: FieldValue.serverTimestamp(),
          expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        });
        logger.info("notifyCustomerOnOrderCancelled: refund notif written", {
          orderId,
          customerId,
          refundAmount: newRefund,
        });
      } catch (err) {
        logger.error("notifyCustomerOnOrderCancelled: refund write failed", {
          orderId,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }
);
