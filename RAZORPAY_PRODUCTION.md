# Razorpay Production Setup (Tasty Kart)

**Never put `RAZORPAY_KEY_SECRET` in Flutter, APK, iOS, Firestore, git, or logs.**

Project: `tastykart-b791a`  
Functions region: `asia-south1`

---

## A. Files created / modified

### Created
| Path | Purpose |
|------|---------|
| `functions/src/index.ts` | `createRazorpayOrder`, `verifyRazorpayPayment`, `razorpayWebhook` |
| `functions/package.json` | Functions deps + build scripts |
| `functions/tsconfig.json` | TypeScript config |
| `functions/.gitignore` | Ignore `node_modules`, `lib`, local secrets |
| `firebase.json` | Functions deploy config |
| `.firebaserc` | Default project `tastykart-b791a` |
| `lib/services/razorpay_payment_service.dart` | Client: create → Checkout → verify |
| `RAZORPAY_PRODUCTION.md` | This guide |
| `firestore.rules.payment.snippet` | Recommended payment field rules |

### Modified
| Path | Change |
|------|--------|
| `pubspec.yaml` | `cloud_functions`, `razorpay_flutter` |
| `lib/screens/checkout/payment_options_screen.dart` | Place order via Razorpay + CF verify |
| `lib/state/cart_controller.dart` | Omit client payment-truth fields |
| `android/app/build.gradle.kts` | `minSdk` ≥ 23 for Razorpay |
| `.gitignore` | Secrets + functions artifacts |

---

## B. Firebase Secret Manager setup

Run from the repo root (interactive — paste values when prompted; **do not** put them in files):

```bash
cd /Users/pc/Desktop/ACS-018/tasty_kart
firebase login
firebase use tastykart-b791a

firebase functions:secrets:set RAZORPAY_KEY_ID
# paste: rzp_live_… (Key ID only)

firebase functions:secrets:set RAZORPAY_KEY_SECRET
# paste: Key Secret (never commit)

firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
# paste: webhook signing secret from Razorpay Dashboard → Webhooks
```

Verify secret names (values are not shown):

```bash
firebase functions:secrets:access RAZORPAY_KEY_ID
# Prefer listing without dumping secrets in shared terminals when possible.
```

Optional staging project: create a second Firebase project and set `rzp_test_…` secrets there; keep production secrets only on `tastykart-b791a`.

---

## C. Firebase deployment

```bash
cd /Users/pc/Desktop/ACS-018/tasty_kart/functions
npm install
npm run build

cd ..
firebase deploy --only functions
```

After deploy, note the webhook URL:

```
https://asia-south1-tastykart-b791a.cloudfunctions.net/razorpayWebhook
```

(Exact URL appears in `firebase deploy` output.)

Enable Blaze plan if not already (required for outbound Razorpay API + secrets).

---

## D. Razorpay Dashboard webhook

1. Razorpay Dashboard → **Settings → Webhooks** (Live mode).
2. URL: `https://asia-south1-tastykart-b791a.cloudfunctions.net/razorpayWebhook`
3. Secret: same value stored as `RAZORPAY_WEBHOOK_SECRET`.
4. Enable at least:
   - `payment.authorized`
   - `payment.captured`
   - `payment.failed`
   - `refund.created`
   - `refund.processed`
5. Save. Send a test event and confirm `200` in Functions logs (`firebase functions:log`).

---

## E. Firestore security rules (payment fields)

Admin currently has public write on `orders` — **lock this down before relying on production payments**.

Recommended constraints (merge into Admin rules; coordinate with Admin repo):

See `firestore.rules.payment.snippet`.

Clients **must not** write:

- `paymentStatus`
- `paymentVerified`
- `razorpayPaymentId`
- `razorpayOrderId`
- `paidAmount` / `paidAmountPaise`

Only Admin SDK (Cloud Functions) may set those.

Also restrict:

- `paymentEvents/{id}` — Admin only
- `webhookEvents/{id}` — Admin only

---

## F. Production testing checklist

- [ ] Secrets set in Firebase (Key ID live, Key Secret live, Webhook secret)
- [ ] Functions deployed to `asia-south1`
- [ ] Webhook URL configured in **Live** Razorpay dashboard
- [ ] No `rzp_test_` or secret strings in Flutter / git
- [ ] Signed-in user places order → Checkout opens with **live** Key ID
- [ ] Successful payment → `{ success: true, verified: true }` → Track Order
- [ ] Close Checkout → order stays unpaid; no success UI
- [ ] Kill app after payment → webhook sets `paymentStatus: paid`, `paymentVerified: true`
- [ ] Duplicate verify / webhook → no double credit (check `paymentEvents`)
- [ ] Amount tampering on client → CF rejects / uses Firestore total
- [ ] Failed payment → `paymentStatus: failed`
- [ ] Refund webhook → `paymentStatus: refunded` / `refund_pending`

---

## G. Verify Key Secret is NOT in the APK

```bash
# Build release APK / AAB
flutter build apk --release

# Search for secret fragments (use a short unique substring of the secret ONLY on a secure machine)
# Prefer searching for the secret name / accidental hardcodes:
unzip -p build/app/outputs/flutter-apk/app-release.apk classes*.dex 2>/dev/null | strings | grep -i razorpay | head
strings build/app/outputs/flutter-apk/app-release.apk | grep -E 'rzp_live_|KEY_SECRET|key_secret' || echo "No secret markers found"

# Better: grep the Dart source / assets only
rg -n "rzp_live_|RAZORPAY_KEY_SECRET|key_secret" lib/ android/ ios/ assets/ || echo "Clean in app sources"
```

Expected: Key ID may appear only at runtime from CF response (not hardcoded). **Key Secret must never appear.**

---

## H. Rotate credentials if compromised

1. Razorpay Dashboard → **API Keys** → regenerate Key Secret (or create new key pair).
2. Update webhook secret if exposed.
3. Re-set Firebase secrets:

```bash
firebase functions:secrets:set RAZORPAY_KEY_ID
firebase functions:secrets:set RAZORPAY_KEY_SECRET
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
firebase deploy --only functions
```

4. Update Razorpay webhook secret to match.
5. Invalidate old keys in Razorpay.
6. Audit Firestore `orders` for suspicious unpaid → paid transitions.
7. Because credentials were pasted in chat, **rotate Key Secret immediately** after first successful setup.

---

## Place-order flow (implemented)

```
Pay Now
  → create Firestore orders/{id} (draft; no payment truth fields)
  → callable createRazorpayOrder(orderId)   // amount from Firestore
  → Razorpay Checkout (Key ID from CF)
  → callable verifyRazorpayPayment(...)     // HMAC + fetch payment
  → success UI ONLY if { success: true, verified: true }
  → else snackbar (webhook may still mark paid later)
```

---

## App-killed recovery

If Checkout succeeds but Flutter never calls verify:

1. Razorpay sends `payment.captured` / `payment.authorized` to `razorpayWebhook`
2. Signature verified with `RAZORPAY_WEBHOOK_SECRET`
3. Order updated via Admin SDK: `paymentStatus: paid`, `paymentVerified: true`
4. `paymentEvents/{paymentId}` prevents duplicate processing
