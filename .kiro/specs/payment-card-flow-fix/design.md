# Payment Card Flow Fix — Bugfix Design

## Overview

Three interconnected bugs make card payment completely non-functional in the Tasty Kart Flutter user app:

1. **Saved cards never shown** — `PaymentOptionsScreen` has no code to fetch or render saved cards, so returning users always see an empty list.
2. **"Pay Now" button hidden for card** — A `if (_selected != 'card')` guard unconditionally hides the action button whenever the card payment path is active, making it impossible to complete payment.
3. **Card details never persisted** — `CardDetailsScreen` pops `true` on valid submission but writes nothing to Firestore, so cards vanish on the next visit.

The fix adds a `SavedCard` model, a `SavedCardService`, wires Firestore persistence into `CardDetailsScreen`, and replaces the broken button guard and static card tile in `PaymentOptionsScreen` with a live `StreamBuilder` display. No changes touch the UPI, COD, Razorpay, or order-creation paths.

---

## Glossary

- **Bug_Condition (C)**: Any of the three defective code paths identified in requirements 1.1–1.4.
- **Property (P)**: The desired correct behavior for each bug condition — cards shown, button always visible, details persisted.
- **Preservation**: The UPI, COD, auth-guard, validation, and Razorpay flows that must remain byte-for-byte identical in behavior after the fix.
- **`SavedCard`**: New model class at `lib/models/saved_card.dart` representing one stored payment card.
- **`SavedCardService`**: New service at `lib/services/saved_card_service.dart` encapsulating Firestore reads/writes for `users/{uid}/savedCards`.
- **`savedCards` sub-collection**: Firestore path `users/{uid}/savedCards/{cardId}` — one document per saved card under the Auth user's node.
- **`_selected`**: State variable in `PaymentOptionsScreen` tracking the chosen payment method; extended to support `'savedCard_{cardId}'` values.
- **`isBugCondition(input)`**: Pseudocode predicate returning `true` for any input that exercises one of the three defective paths.

---

## Bug Details

### Bug Condition

The bug manifests across three distinct code paths. Each has its own sub-condition:

**C1 — No saved cards rendered**: `PaymentOptionsScreen` has no `StreamBuilder` or fetch call for `users/{uid}/savedCards`; the widget tree is fully static.

**C2 — Pay Now button gated on `_selected != 'card'`**: The bottom action button is wrapped in `if (_selected != 'card')`, so selecting any card-related option (saved card or new card entry) hides the button.

**C3 — Card not written to Firestore**: `CardDetailsScreen._onMakePayment()` calls `Navigator.pop(context, true)` immediately after validation without executing any Firestore write.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input — a PaymentScreenAction | CardSubmitAction
  OUTPUT: boolean

  IF input IS PaymentScreenAction THEN
    RETURN (input.type == OPEN_SCREEN AND no savedCards fetched)  // C1
           OR (input.type == SELECT_CARD AND Pay Now button absent)  // C2

  IF input IS CardSubmitAction THEN
    RETURN (input.validationPassed == true AND firestoreWriteOccurred == false)  // C3

  RETURN false
END FUNCTION
```

### Examples

- **C1**: User has two previously saved Visa cards. Opens payment options screen → only "+ Add New Card" is shown; saved cards never appear.
- **C2**: User taps "+ Add New Card", enters valid details, returns with `paid == true` → `_selected` becomes `'card'` → Pay Now button disappears; user is stuck.
- **C2 (saved card)**: User selects a saved card tile → `_selected == 'savedCard_xyz'` contains `'card'` suffix logic is wrong → button hidden.
- **C3**: User enters a valid Visa card, taps "Make Payment" → app pops back, triggers Razorpay, but returns on next visit to an empty saved cards list.
- **Edge case C3**: Firestore write fails mid-flight → app must NOT pop true; it must show an error and stay on the card details screen.

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Tapping PhonePe / Google Pay / UPI / Paytm tiles and then "Pay Now" MUST continue to route through `RazorpayPaymentService.payForOrder` identically.
- Tapping "Place Order" with COD selected MUST continue to create the Firestore order doc immediately with `paymentMethod: 'Cash on Delivery'`.
- Tapping "+ Add New Card" MUST continue to push `CardDetailsScreen` and await its `bool?` result.
- Invalid card form submissions (short number, empty name, bad CVV, malformed expiry) MUST continue to show the validation snackbar and stay on `CardDetailsScreen` without popping.
- Auth guard (user not signed in, cart empty, delivery address missing) checks MUST continue to fire before any payment logic.
- Razorpay unverified payment snackbar path MUST continue to not create an order doc.
- Block-check (`AuthService.enforceCustomerAccess`) MUST continue to fire and clear the cart on `CustomerBlockedException`.

**Scope:**
All inputs that do NOT involve the three bug conditions should be completely unaffected. This includes:
- All UPI method selections and payment execution
- COD order creation flow
- Validation failure path in `CardDetailsScreen`
- All auth-guard short-circuit paths
- Razorpay success/failure/unverified branches

---

## Hypothesized Root Cause

1. **Missing stream subscription (C1)**: The `PaymentOptionsScreen` widget was built with a hardcoded static list. No call to a saved-cards collection was ever wired in, likely because the persistence layer (C3) was also missing — the two bugs are coupled.

2. **Overly broad button guard (C2)**: The `if (_selected != 'card')` condition was likely intended to hide the bottom button while the user is inside `CardDetailsScreen` (which has its own "Make Payment" button). However, the condition also fires after the user returns from `CardDetailsScreen` with `paid == true` and `_selected` is set to `'card'`, trapping them with no way to re-trigger payment. The guard should have been removed entirely since `CardDetailsScreen` owns its own CTA.

3. **Incomplete `_onMakePayment` implementation (C3)**: `CardDetailsScreen` was scaffolded with validation logic but the Firestore write was never implemented. The `Navigator.pop(context, true)` exists, confirming the intent to save-then-pop, but the write call is absent.

4. **No `SavedCard` model or service**: Because neither `SavedCard` nor `SavedCardService` exist, there is no infrastructure for any of the three fixes to call into, reinforcing that all three bugs have a common root in an incomplete feature implementation.

---

## Correctness Properties

Property 1: Bug Condition — Saved Cards Displayed on Screen Open

_For any_ signed-in user who has at least one document in `users/{uid}/savedCards`, opening `PaymentOptionsScreen` SHALL render one selectable tile per saved card above the "+ Add New Card" tile, showing masked number (`•••• {last4}`), cardholder name or nickname, and card type.

**Validates: Requirements 2.1, 2.4**

Property 2: Bug Condition — Pay Now Button Always Visible

_For any_ payment method selection state (UPI, COD, saved card, or `_selected == 'card'`), the "Pay Now" / "Place Order" button at the bottom of `PaymentOptionsScreen` SHALL always be rendered and tappable.

**Validates: Requirements 2.2**

Property 3: Bug Condition — Card Details Persisted to Firestore

_For any_ valid card form submission in `CardDetailsScreen` (all validation passes), the system SHALL write a `SavedCard` document to `users/{uid}/savedCards/{cardId}` before popping `true`, and SHALL NOT pop if the write throws an exception.

**Validates: Requirements 2.3**

Property 4: Preservation — UPI and COD Flows Unchanged

_For any_ input where the bug condition does NOT hold (user selects a UPI method or COD and taps Pay Now), the fixed code SHALL produce exactly the same behavior as the original code — same Razorpay call for UPI, same immediate Firestore order creation for COD.

**Validates: Requirements 3.1, 3.2**

Property 5: Preservation — Validation and Auth Guards Unchanged

_For any_ invalid card input or unauthenticated/empty-cart state, the fixed code SHALL continue to show the appropriate error snackbar and not proceed, identical to the original behavior.

**Validates: Requirements 3.4, 3.5, 3.6**

---

## Fix Implementation

### New File: `lib/models/saved_card.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SavedCard {
  final String id;         // Firestore doc id
  final String last4;      // Last 4 digits of card number
  final String holderName;
  final String expiry;     // MM/YY
  final String? nickname;
  final String cardType;   // 'Visa' | 'Mastercard' | 'Other'
  final DateTime createdAt;

  const SavedCard({
    required this.id,
    required this.last4,
    required this.holderName,
    required this.expiry,
    required this.cardType,
    this.nickname,
    required this.createdAt,
  });

  /// Infer card type from the first digit of the raw card number.
  static String inferCardType(String rawNumber) {
    final first = rawNumber.trimLeft().isNotEmpty ? rawNumber.trimLeft()[0] : '';
    if (first == '4') return 'Visa';
    if (first == '5') return 'Mastercard';
    return 'Other';
  }

  Map<String, dynamic> toMap() => {
    'last4': last4,
    'holderName': holderName,
    'expiry': expiry,
    'nickname': nickname,
    'cardType': cardType,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory SavedCard.fromMap(String id, Map<String, dynamic> map) {
    final raw = map['createdAt'];
    final createdAt = raw is Timestamp
        ? raw.toDate()
        : DateTime.now();

    return SavedCard(
      id: id,
      last4: (map['last4'] as String? ?? ''),
      holderName: (map['holderName'] as String? ?? ''),
      expiry: (map['expiry'] as String? ?? ''),
      nickname: map['nickname'] as String?,
      cardType: (map['cardType'] as String? ?? 'Other'),
      createdAt: createdAt,
    );
  }

  /// Display label — nickname if set, else masked number.
  String get displayLabel => nickname?.isNotEmpty == true
      ? nickname!
      : '•••• $last4';
}
```

**Key decisions:**
- CVV is intentionally excluded — never persisted.
- `last4` is extracted from the raw 16-digit number at save time; the full number is never written.
- `inferCardType` is a static helper so `CardDetailsScreen` can call it without instantiating a service.

---

### New File: `lib/services/saved_card_service.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/saved_card.dart';

class SavedCardService {
  SavedCardService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('savedCards');

  /// Writes a new SavedCard document. Throws on Firestore error.
  static Future<void> saveCard(String uid, SavedCard card) async {
    await _col(uid).add(card.toMap());
  }

  /// Streams the list of saved cards ordered by createdAt descending.
  static Stream<List<SavedCard>> getSavedCards(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SavedCard.fromMap(d.id, d.data()))
            .toList());
  }
}
```

**Key decisions:**
- Uses a sub-collection (`users/{uid}/savedCards`) rather than an array field — enables ordered queries and avoids document-size growth.
- `saveCard` uses `.add()` (auto-generated Firestore ID) so no ID collision handling is needed.
- `getSavedCards` streams rather than futures so `PaymentOptionsScreen` updates in real-time if a card is added mid-session.

---

### Changes: `lib/screens/checkout/card_details_screen.dart`

**In `_onMakePayment()`** — replace the current body (after validation passes) with:

```dart
void _onMakePayment() async {
  final error = _validateCard();
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), behavior: SnackBarBehavior.floating,
               backgroundColor: const Color(0xFFB32B2C)),
    );
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    // Signed-out edge case — let parent handle it via the null pop.
    Navigator.pop(context, false);
    return;
  }

  setState(() => _saving = true);
  try {
    final rawNumber = _number.text.trim();
    final card = SavedCard(
      id: '',  // filled by Firestore .add()
      last4: rawNumber.substring(rawNumber.length - 4),
      holderName: _name.text.trim(),
      expiry: _expiry.text.trim(),
      nickname: _nick.text.trim().isEmpty ? null : _nick.text.trim(),
      cardType: SavedCard.inferCardType(rawNumber),
      createdAt: DateTime.now(),
    );
    await SavedCardService.saveCard(user.uid, card);
    if (!mounted) return;
    Navigator.pop(context, true);
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save card: $e'),
               behavior: SnackBarBehavior.floating,
               backgroundColor: const Color(0xFFB32B2C)),
    );
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}
```

**New state field**: `bool _saving = false;`

**"Make Payment" button change** — disable and show spinner while saving:
```dart
onPressed: _saving ? null : _onMakePayment,
child: _saving
    ? const SizedBox(width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
    : const Text('Make Payment', ...),
```

**No other changes** to validation logic, formatters, or UI layout.

---

### Changes: `lib/screens/checkout/payment_options_screen.dart`

**1. Remove the `if (_selected != 'card')` gate** on the Pay Now button — the `SafeArea`/`Padding`/`ElevatedButton` block at the bottom becomes unconditional.

**2. Replace the static `ListTile` block under "Credit & Debit Cards"** with a `StreamBuilder`:

```dart
StreamBuilder<List<SavedCard>>(
  stream: SavedCardService.getSavedCards(
      FirebaseAuth.instance.currentUser?.uid ?? ''),
  builder: (context, snap) {
    final cards = snap.data ?? [];
    return Column(
      children: [
        // One selectable tile per saved card
        ...cards.map((card) => _SavedCardTile(
          card: card,
          selected: _selected,
          onTap: () => setState(() => _selected = 'savedCard_${card.id}'),
        )),
        // Always-present add-new tile
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFE8E8),
            child: Icon(Icons.credit_card_rounded, color: AppColors.primary),
          ),
          title: const Text('+ Add New Card',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Save And Pay Via Cards'),
          trailing: _RadioDot(selected: _selected == 'card'),
          onTap: () async {
            final paid = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const CardDetailsScreen()),
            );
            if (paid == true && context.mounted) {
              setState(() => _selected = 'card');
              await _completePayment();
            }
          },
        ),
      ],
    );
  },
),
```

**3. New private widget `_SavedCardTile`**:

```dart
class _SavedCardTile extends StatelessWidget {
  const _SavedCardTile({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final SavedCard card;
  final String selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == 'savedCard_${card.id}';
    final icon = card.cardType == 'Visa'
        ? Icons.credit_card_rounded
        : card.cardType == 'Mastercard'
            ? Icons.credit_score_rounded
            : Icons.payment_rounded;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFE8E8),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(card.displayLabel,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${card.cardType}  •  Exp ${card.expiry}'),
      trailing: _RadioDot(selected: isSelected),
      onTap: onTap,
    );
  }
}
```

**4. Update `_methodLabel` getter** to handle saved card selections:

```dart
String get _methodLabel {
  if (_selected.startsWith('savedCard_')) return 'Saved Card';
  switch (_selected) {
    case 'phonepe':  return 'PhonePe';
    case 'gpay':     return 'Google Pay';
    case 'paytm':    return 'Paytm';
    case 'card':     return 'Card';
    case 'cod':      return 'Cash on Delivery';
    default:         return 'UPI';
  }
}
```

**5. Update `_isCod` getter** — no change needed; it remains `_selected == 'cod'`.

**6. No changes** to `_completePayment()`, UPI tiles, COD tile, `_PayTile`, `_RadioDot`, `_Header`, or `RazorpayPaymentService` calls.

---

### Changes: `lib/services/firestore_paths.dart`

Add one constant for the sub-collection name:

```dart
static const savedCards = 'savedCards';
```

Update `SavedCardService` to reference it: `_db.collection(FirestorePaths.users).doc(uid).collection(FirestorePaths.savedCards)`.

---

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first surface counterexamples that demonstrate each bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

---

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate each bug BEFORE implementing the fix, to confirm root cause analysis.

**Test Plan**: Write widget tests that drive the relevant screens and assert the broken behavior is observable. Run on unfixed code to confirm failures match the hypotheses.

**Test Cases**:
1. **C1 — No saved cards rendered** (will fail on unfixed code): Seed Firestore emulator with two saved card documents for `uid`, pump `PaymentOptionsScreen`, assert two `_SavedCardTile` widgets appear → will find zero.
2. **C2 — Pay Now hidden after card selection** (will fail on unfixed code): Pump `PaymentOptionsScreen`, simulate tapping a card tile so `_selected == 'card'`, assert the "Pay Now" `ElevatedButton` is in the tree → will find none.
3. **C3 — No Firestore write on valid submission** (will fail on unfixed code): Pump `CardDetailsScreen`, fill all fields validly, tap "Make Payment", assert a doc was written to `users/{uid}/savedCards` → will find zero writes.
4. **C3 edge — Save failure prevents pop** (to confirm after fix): Mock `SavedCardService.saveCard` to throw, fill valid card, tap "Make Payment", assert screen does NOT pop and error snackbar is shown.

**Expected Counterexamples**:
- `StreamBuilder` for saved cards is absent → zero tiles rendered.
- `if (_selected != 'card')` evaluates to `false` → button widget removed from tree.
- No Firestore write call in `_onMakePayment` → collection stays empty.

---

### Fix Checking

**Goal**: Verify that for all inputs where a bug condition holds, the fixed code produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := fixedCode(input)
  ASSERT expectedBehavior(result)
END FOR
```

**Test Cases** (run on FIXED code):
1. Seed two saved cards → pump screen → assert two `_SavedCardTile` widgets rendered.
2. Tap saved card tile → assert `_selected == 'savedCard_{id}'` → assert Pay Now button visible.
3. Tap card tile so `_selected == 'card'` → assert Pay Now button still in tree.
4. Fill valid card form → tap Make Payment → assert Firestore doc exists with correct `last4`, `holderName`, `expiry`, `cardType`; CVV NOT present.
5. `SavedCardService.saveCard` throws → assert screen stays open, error snackbar shown, `Navigator.pop` NOT called.

---

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, fixed code behaves identically to original.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalCode(input) == fixedCode(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because it generates many input combinations automatically, catching edge cases that manual tests miss.

**Test Cases**:
1. **UPI Preservation**: Select Google Pay, tap Pay Now → assert `RazorpayPaymentService.payForOrder` called with `preferredMethodLabel: 'Google Pay'` — same as before.
2. **COD Preservation**: Select COD, tap Place Order → assert `FirestoreService.createOrder` called with `paymentMethod: 'Cash on Delivery'`; no Razorpay call.
3. **Validation Preservation**: Fill card number with 15 digits, tap Make Payment → assert snackbar shown, no Firestore write, no pop.
4. **Auth Guard Preservation**: Sign out user, tap any Pay Now → assert "Please sign in" snackbar; no order created.
5. **Back navigation**: Tap back arrow in `CardDetailsScreen` → `Navigator.pop(context)` (no value) → `paid` is `null` → assert `_completePayment` is NOT called.

---

### Unit Tests

- `SavedCard.inferCardType` for inputs starting with '4', '5', '3', '6', and empty string.
- `SavedCard.fromMap` round-trips through `toMap` with and without `nickname`.
- `SavedCard.displayLabel` returns nickname when set, masked number otherwise.
- `_validateCard` in `CardDetailsScreen` for all invalid permutations (short number, empty name, short CVV, bad expiry formats).
- `_ExpiryDateFormatter` auto-inserts '/' at position 2 correctly for partial and complete inputs.

### Property-Based Tests

- Generate random 16-digit card numbers: assert `last4` always equals the final 4 characters and `cardType` matches the first-digit rule.
- Generate random sets of saved cards (0–20): assert `StreamBuilder` renders exactly `cards.length` `_SavedCardTile` widgets plus one "+ Add New Card" tile.
- Generate random `_selected` values (valid UPI ids, 'cod', 'savedCard_*'): assert Pay Now button is always present in the widget tree.
- Generate random valid card form inputs: assert Firestore doc count increases by exactly 1 after each submission.

### Integration Tests

- Full card save-and-pay flow: fill new card → saved to Firestore → `PaymentOptionsScreen` stream updates → saved card tile appears → tap tile → Pay Now → Razorpay called.
- Saved card persists across screen lifecycle: save card, pop to previous screen, re-open `PaymentOptionsScreen`, assert card tile still rendered from Firestore.
- COD full flow: select COD → Place Order → order doc in Firestore → `TrackOrderScreen` pushed — unchanged from original.
