# Bugfix Requirements Document

## Introduction

The Tasty Kart Flutter user app has three interconnected bugs in the card payment flow. When a user selects or enters card payment details on the payment options screen, no saved cards are displayed, the "Pay Now" button disappears entirely for the card payment path, and card details entered by the user are never persisted to Firestore — making saved cards unavailable on future visits. These bugs together make card payment completely non-functional: users cannot pay by card and any details they enter are lost.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the user has previously saved one or more cards and navigates to the payment options screen THEN the system shows no saved cards under "Credit & Debit Cards" — only the "+ Add New Card" tile is rendered

1.2 WHEN the user selects the card payment option (i.e., `_selected == 'card'`) THEN the system hides the "Pay Now" / "Place Order" button entirely, leaving no way to proceed with payment

1.3 WHEN the user completes and submits valid card details in `CardDetailsScreen` THEN the system pops `true` back to the parent screen but does not save any card data to Firestore

1.4 WHEN the user returns to the payment options screen after previously entering card details THEN the system shows no record of the previously entered card because nothing was persisted

### Expected Behavior (Correct)

2.1 WHEN the user has previously saved one or more cards and navigates to the payment options screen THEN the system SHALL fetch the user's saved cards from Firestore (`users/{uid}/savedCards`) and display each card as a selectable tile (showing masked card number last 4 digits, cardholder name, and optional nickname) with a radio dot, above the "+ Add New Card" tile

2.2 WHEN the user selects any payment option including a saved card or the card payment method THEN the system SHALL display the "Pay Now" button regardless of which option is selected, so the user can always proceed to complete payment

2.3 WHEN the user completes and submits valid card details in `CardDetailsScreen` THEN the system SHALL save the card to Firestore at `users/{uid}/savedCards/{cardId}` with the fields: masked last 4 digits of card number, cardholder name, expiry date (MM/YY), optional nickname, and card type (Visa/Mastercard inferred from first digit) — then pop `true` so the parent triggers payment

2.4 WHEN a card is saved to Firestore and the user navigates to the payment options screen THEN the system SHALL display that card in the saved cards list as a selectable option

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user selects a UPI option (PhonePe, Google Pay, UPI, Paytm) and taps "Pay Now" THEN the system SHALL CONTINUE TO initiate the Razorpay payment flow for that method without any change

3.2 WHEN the user selects "Cash on Delivery" and taps "Place Order" THEN the system SHALL CONTINUE TO create the order in Firestore immediately with payment method "Cash on Delivery" and navigate to the order tracking screen

3.3 WHEN the user taps "+ Add New Card" THEN the system SHALL CONTINUE TO navigate to `CardDetailsScreen` and await the result before selecting the card and triggering payment

3.4 WHEN the user submits invalid card details in `CardDetailsScreen` (e.g., card number shorter than 16 digits, empty name, invalid CVV, missing or malformed expiry) THEN the system SHALL CONTINUE TO show the validation error snackbar and remain on the card details screen without popping or saving

3.5 WHEN the user is not signed in or the cart is empty THEN the system SHALL CONTINUE TO show the appropriate error snackbar and not proceed with order creation

3.6 WHEN a payment via Razorpay is not verified THEN the system SHALL CONTINUE TO show the unverified payment snackbar without creating an order document in Firestore
