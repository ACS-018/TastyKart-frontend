import * as crypto from "crypto";
import {initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type Transaction,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
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
  const deliveryFee = Number(order.deliveryFee ?? 0);
  const platformFee = Number(order.platformFee ?? 0);
  const discount = Number(order.discount ?? 0);
  const recomputed = itemsSum + tax + deliveryFee + platformFee - discount;

  if (total <= 0) {
    throw new HttpsError("failed-precondition", "Order has no payable total.");
  }
  if (items.length > 0 && Math.abs(recomputed - total) > 1) {
    logger.warn("Order amount mismatch vs line items", {
      orderId: order.id,
      total,
      recomputed,
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

async function applyPaidUpdate(params: {
  firestoreOrderId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  amountPaise: number;
  currency: string;
  source: "verify" | "webhook";
}): Promise<void> {
  const orderRef = db.collection("orders").doc(params.firestoreOrderId);
  await db.runTransaction(async (tx: Transaction) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Order not found.");
    }
    const data = snap.data() || {};
    if (data.paymentVerified === true && data.paymentStatus === "paid") {
      return;
    }
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

    tx.update(orderRef, {
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
    });
  });
}

async function applyFailedUpdate(
  firestoreOrderId: string,
  reason: string
): Promise<void> {
  const orderRef = db.collection("orders").doc(firestoreOrderId);
  await orderRef.set(
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
 * Input: { orderId: string } — Firebase order doc id only.
 * Amount is always read/validated from Firestore (never from client).
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

    const orderRef = db.collection("orders").doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Order not found.");
    }
    const order = snap.data() as OrderDoc;

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

    const orderRef = db.collection("orders").doc(firestoreOrderId);
    const snap = await orderRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Order not found.");
    }
    const order = snap.data() as OrderDoc;

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
            const q = await db
              .collection("orders")
              .where("razorpayOrderId", "==", razorpayOrderId)
              .limit(1)
              .get();
            if (!q.empty) {
              firestoreOrderId = q.docs[0].id;
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
            const orderSnap = await db
              .collection("orders")
              .doc(firestoreOrderId)
              .get();
            if (
              orderSnap.exists &&
              orderSnap.data()?.paymentVerified !== true
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
            const q = await db
              .collection("orders")
              .where("razorpayOrderId", "==", razorpayOrderId)
              .limit(1)
              .get();
            if (!q.empty) firestoreOrderId = q.docs[0].id;
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
