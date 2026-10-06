# TastyKart Customer App — Complete Guide

Single reference for the **TastyKart** Flutter customer app: Firebase usage, folder structure, brand colors, responsive UI, state, navigation, payments, and release signing.

| | |
|---|---|
| **App display name** | TastyKart (`AppConstants.appName`) |
| **Package / applicationId** | `com.arrowcoders.foodapp` |
| **Firebase project** | `tastykart-b791a` |
| **Pairs with** | TastyKart Admin (same Firestore + Auth project) |
| **Policy** | Do **not** invent new top-level collections or change Admin security rules from this app |

Related docs: `FIREBASE_AND_PROJECT_OVERVIEW.md`, `CUSTOMER_ADMIN_INTEGRATION.md`, `RAZORPAY_PRODUCTION.md`, `admin.md`.

---

## 1. What the app does

TastyKart is a food-ordering client. Customers:

1. Sign in (email / Google / phone OTP)
2. Browse restaurants, banners, categories, and search
3. Filter veg / non-veg and cuisines
4. Save favourites and delivery addresses
5. Build a cart and checkout (Cash on Delivery or Razorpay)
6. Track orders, leave reviews, manage profile

Admin (separate app) owns restaurants, menus, banners, fees, customer block/unblock, and order ops. This app **reads/writes only within Admin’s shared schema**.

---

## 2. High-level architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter UI (screens / widgets)                             │
│       ↓                                                     │
│  State scopes (Cart / Favourites / DietFilter)              │
│       ↓                                                     │
│  Services (Auth, Firestore, Razorpay, Search, Address…)     │
└────────────┬──────────────────────────────┬─────────────────┘
             │                              │
             ▼                              ▼
   Firebase Auth + Firestore      Cloud Functions (asia-south1)
   project: tastykart-b791a       createRazorpayOrder
                                  verifyRazorpayPayment
                                  razorpayWebhook
```

**Boot sequence** (`lib/main.dart`):

1. `Firebase.initializeApp()`
2. Create `CartController`, `FavoritesController`, `DietFilterController`
3. Listen to `settings/admin` → apply platform charges to cart
4. Wrap app: `CartScope` → `DietFilterScope` → `FavoritesScope` → `MaterialApp`
5. `home: AuthGate` (login vs home based on Auth + block status)

---

## 3. Folder structure

### Top-level

```
tasty_kart/
├── lib/                    # Flutter source
├── android/                # Android (Play Store, signing, google-services.json)
├── ios/                    # iOS
├── assets/
│   ├── Images/             # Logo (TastyKart_1.png), etc.
│   └── Icons/              # Social / UI icons
├── functions/              # Cloud Functions (Razorpay)
├── test/
├── pubspec.yaml
├── firebase.json
└── .firebaserc
```

### `lib/` layout

```
lib/
├── main.dart                 # Firebase init, scopes, MaterialApp
├── constants/
│   ├── app_constants.dart    # AppConstants.appName = "TastyKart"
│   ├── color_constants.dart  # AppColors brand palette
│   ├── image_constants.dart  # AppImages.logo, etc.
│   └── map_constants.dart    # Default map camera / helpers
├── models/                   # Firestore-backed domain models
├── services/                 # Auth, Firestore, payments, geo, search
├── state/                    # ChangeNotifier + InheritedNotifier scopes
├── screens/                  # Feature UI by area
├── widgets/                  # Shared feature widgets
├── global_widgets/           # AppButton, AppTextField, LoadingOverlay
└── utils/                    # Responsive, AppNavigation, AppFeedback
```

### Screens by area

| Folder | Screens / role |
|--------|----------------|
| `screens/auth_gate.dart` | Root gate: Login ↔ Home; block enforcement |
| `screens/auth/` | Login, Signup, Forgot password, OTP, Reset password |
| `screens/Home/` | Home shell + bottom nav; components (banners, grid, filters…) |
| `screens/restaurant/` | Menu, addons sheet |
| `screens/checkout/` | Cart summary, payment options (COD + Razorpay), track order |
| `screens/location/` | Select / save delivery addresses + map |
| `screens/search/` | Global search (restaurants + dishes) |
| `screens/category/` | Category → restaurant list |
| `screens/profile/` | Profile, edit, favourites, order history, settings |
| `screens/notifications/` | Notifications list |
| `screens/order/` | Delivered, rate & review |

### Services

| Service | Responsibility |
|---------|----------------|
| `AuthService` | Login / signup / Google / phone OTP / logout / profile sync / block enforce |
| `CustomerAccountService` | Resolve & watch `customers` docs; assert not blocked |
| `FirestoreService` | Catalog streams, `createOrder`, reviews, settings |
| `FirestorePaths` | Shared collection name constants |
| `AddressService` | `customers/{uid}.addresses[]` |
| `FavoritesService` | `customers/{uid}.favorites[]` |
| `RazorpayPaymentService` | CF create → Checkout → CF verify |
| `BannerNavigationService` | Banner tap → restaurant or URL |
| `SearchService` | Client-side filter over loaded catalog |
| `GeocodingService` / `PlacesService` | Location / Places helpers |

### Models (selected)

`Restaurant`, `FoodItem`, `DeliveryAddress`, `FavoriteRestaurant`, `CustomerAccount`, `AppBanner`, plus `admin_models.dart` (`PlatformCharges`, order DTOs, etc.).

---

## 4. Firebase handling

### Products in use

| Product | How |
|---------|-----|
| **Firebase Auth** | Email/password, Google Sign-In, Phone OTP, password reset |
| **Cloud Firestore** | Catalog, customers, orders, banners, notifications, settings |
| **Cloud Functions** | Razorpay order create / verify / webhook (`asia-south1`) |
| **Analytics** | Android Gradle BoM only (not a Flutter package) |
| **Storage** | Not used in the Flutter customer app |

Config files:

- Android: `android/app/google-services.json`
- iOS: `GoogleService-Info.plist` (when present)
- Init: `Firebase.initializeApp()` in `main.dart`

### Auth flows

| Flow | Behaviour |
|------|-----------|
| Email login | `signInWithEmailAndPassword` → block check → profile sync |
| Signup | Create Auth user → write `users/{uid}` + `customers/{uid}` |
| Google | `GoogleSignIn` → Firebase credential → block check → profile |
| Phone OTP | `verifyPhoneNumber` / `confirmPhoneOtp` |
| Forgot password | `sendPasswordResetEmail` (does not reveal if email exists) |
| Logout | Firebase + Google sign-out → AuthGate shows Login; stack cleared |

Profile sync:

- Writes `users/{uid}` with `role: 'customer'`
- Merges `customers/{uid}` for Admin
- **Never overwrites** Admin `status` / `blockedAt` / `blockedReason` on existing customer docs (new docs start as `active`)

### Customer block enforcement

Source of truth: Firestore `customers` (`status`: `active` | `blocked`).

1. After login: resolve `customers/{auth.uid}`, else match by email/phone
2. If blocked → logout immediately + message: *Your account has been blocked. Contact support.*
3. AuthGate streams status; re-checks on app resume
4. Checkout re-fetches status before creating an order
5. Mid-session Admin block → forced logout without needing reinstall

### Firestore collections (`FirestorePaths`)

| Collection | Customer app use |
|------------|------------------|
| `users` | Auth profile mirror (`role: customer`) |
| `customers` | Profile, addresses[], favorites[], block status |
| `restaurants` | Home / search / menu |
| `restaurantCategories` / `foodCategories` | Browse filters |
| `foodItems` / `addons` | Menu + cart |
| `banners` | Home carousel + tap actions |
| `orders` | Create, history, tracking |
| `reviews` | Post-delivery ratings |
| `notifications` | In-app list |
| `settings` / doc `admin` | Platform fees (tax, delivery, etc.) |
| `offers` / `coupons` / `subscriptions` | Available for Admin-aligned features |

### Orders & payments

**Create order** → `orders/{id}` via `FirestoreService.createOrder` (payload from `CartController.toAdminOrderPayload`).

| Method | Flow |
|--------|------|
| **Cash on Delivery** | Create order with `paymentMethod: Cash on Delivery` → clear cart → Track Order (no Razorpay) |
| **Razorpay** | Create draft order → `createRazorpayOrder` CF → Checkout SDK → `verifyRazorpayPayment` CF → Track only if server `verified` |

**Security:** Razorpay **Key Secret stays on Cloud Functions only**. Client never decides payment truth.

Functions (region `asia-south1`):

- `createRazorpayOrder`
- `verifyRazorpayPayment`
- `razorpayWebhook` (reconcile if app dies after gateway success)

### Addresses & favourites

Stored as **array fields on** `customers/{uid}` (not separate subcollections), so they work with Admin customer-doc rules:

- `addresses[]` + `defaultAddress`
- `favorites[]`

---

## 5. Brand colors (`AppColors`)

Defined in `lib/constants/color_constants.dart`. Use these everywhere instead of hard-coded hex in new UI.

| Token | Hex | Role |
|-------|-----|------|
| `primary` | `#B32B2C` | Brand red — AppBars, buttons, seed color |
| `primaryLight` | `#FF8C5A` | Accents / highlights |
| `primaryDark` | `#E04E1A` | Darker accent |
| `background` | `#FEF5EC` | App / scaffold cream background |
| `textDark` | `#1A1A1A` | Primary text |
| `textMedium` | `#6B6B6B` | Secondary text |
| `textLight` | `#AAAAAA` | Hints / muted |
| `white` | `#FFFFFF` | Cards, contrast on primary |
| `divider` | `#EEEEEE` | Separators |
| `inputBorder` | `#E0D5C8` | Form borders |
| `inputFill` | `#FFFAF5` | Form fill |
| `error` | `#E53935` | Errors / destructive |
| `success` | `#43A047` | Success feedback |

**Theme wiring** (`main.dart`):

- `ColorScheme.fromSeed(seedColor: AppColors.primary)`
- `scaffoldBackgroundColor: AppColors.background`
- Razorpay Checkout theme color: `#B32B2C`

---

## 6. Responsive UI

Utility: `lib/utils/responsive.dart`.

### Breakpoints (`AppBreakpoints`)

| Device | Width |
|--------|--------|
| Mobile | `< 600` |
| Tablet | `600` – `1024` |
| Desktop | `> 1024` |

### API

```dart
final r = Responsive.of(context);

r.isMobile / r.isTablet / r.isDesktop
r.wp(50)  // 50% of width
r.hp(10)  // 10% of height
r.responsive(mobile: 16.0, tablet: 24.0, desktop: 32.0)
```

Helpers:

- `ResponsiveBuilder` — rebuild with `Responsive` when size changes
- `BreakpointWidget` — swap entire layouts per breakpoint

### Where it’s used today

Primarily **auth** screens (login, forgot password, OTP, `AuthHeader` logo sizing).

### Other adaptive patterns

- `MediaQuery.padding` / safe areas on headers and bottom bars
- Keyboard-aware forms (`resizeToAvoidBottomInset` / scroll views)
- Home uses a **mobile-first** bottom navigation (`IndexedStack` tabs); tablet/desktop can extend via `BreakpointWidget` later

---

## 7. State management

**No Provider / Riverpod / Bloc.** Pattern: `ChangeNotifier` + `InheritedNotifier` scopes.

```
CartScope
  └─ DietFilterScope
       └─ FavoritesScope
            └─ MaterialApp → AuthGate
```

| Scope | Controller | Holds |
|-------|------------|--------|
| `CartScope` | `CartController` | Cart lines, addons, address, customer, platform charges, totals |
| `FavoritesScope` | `FavoritesController` | Favourite restaurants (optimistic UI ↔ Firestore) |
| `DietFilterScope` | `DietFilterController` | App-wide Veg / Non-Veg filter |

Access examples:

```dart
final cart = CartScope.of(context);
final favs = FavoritesScope.of(context);
final diet = DietFilterScope.of(context);
```

Use `maybeOf` when the widget might be above the scope (e.g. during logout cleanup).

---

## 8. Navigation & user flows

### Root navigation

- `MaterialApp.navigatorKey` = `AppNavigation.rootNavigatorKey`
- No named routes; screens pushed with `Navigator` / `AppNavigation.push` (slide + fade)
- On logout: `AppNavigation.goToAuthRoot()` pops to first route so Login is visible

### AuthGate

| Auth state | UI |
|------------|-----|
| Loading | Spinner |
| Signed out | `LoginScreen` (link to Signup) |
| Signed in + blocked | Logout + blocked message |
| Signed in + active | `HomeScreen` (after access check) |

### Typical happy path

```
Login / Signup
  → Home (browse / search / favourites)
    → Restaurant menu → addons → cart
      → Cart summary → Payment options
        → COD or Razorpay
          → Track order → Delivered → Rate & review → Home
```

### Home tabs

`IndexedStack`: Home | Order history | Favourites | Profile  
Center FAB → Global Search.

---

## 9. UX helpers

| Helper | Role |
|--------|------|
| `AppFeedback` | Haptics + success/error snackbars |
| `AppNavigation` | Consistent page transitions + root navigator |
| `AsyncStateMessage` | Empty / error / loading copy for lists |
| `LoadingOverlay` | Full-screen loading on auth forms |

---

## 10. Android release (Play Store)

| Item | Value |
|------|--------|
| Display name | **TastyKart** (`@string/app_name`) |
| applicationId | `com.arrowcoders.foodapp` |
| Signing | `android/key.properties` + `android/app/arrowcoders.jks` |
| Alias | `release-key` |
| Gradle | `signingConfigs.release` on `buildTypes.release` |
| minSdk | ≥ 23 (Razorpay) |

Build:

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

**Secrets:** `key.properties` and `*.jks` are gitignored under `android/` — keep them local / in a secure vault. Never commit passwords.

Play Console store listing title should also be set to **TastyKart** (separate from the launcher label in the AAB).

---

## 11. Key dependencies

| Package | Use |
|---------|-----|
| `firebase_core` / `firebase_auth` / `cloud_firestore` / `cloud_functions` | Backend |
| `google_sign_in` | Google login |
| `razorpay_flutter` | Checkout UI |
| `google_maps_flutter` / `geolocator` / `geocoding` | Maps & location |
| `http` / `url_launcher` | Places / banner web links |

---

## 12. Feature checklist

- [x] Email, Google, phone OTP auth + password reset  
- [x] Admin customer block / unblock enforcement  
- [x] Home banners, categories, featured, restaurant grid  
- [x] Veg / Non-Veg + cuisine filters  
- [x] Global search (restaurants & dishes)  
- [x] Restaurant menu + addons + cart  
- [x] Favourites  
- [x] Delivery addresses (list + map / Places)  
- [x] Checkout: Cash on Delivery + Razorpay  
- [x] Order history & track order  
- [x] Notifications  
- [x] Profile / edit / settings  
- [x] Platform fees from Admin `settings/admin`  

---

## 13. Conventions for contributors

1. **Collections** — only use names in `FirestorePaths`; match Admin schemas.  
2. **Colors** — use `AppColors`; don’t introduce one-off brand hex.  
3. **App name** — use `AppConstants.appName` for user-visible brand text.  
4. **Responsive** — prefer `Responsive.of(context)` for new multi-size layouts.  
5. **Payments** — never put Razorpay Key Secret in the Flutter app; always verify via Cloud Functions.  
6. **Customer status** — never overwrite Admin block fields when syncing profile.  
7. **Rules** — do not deploy or edit Admin Firestore/Storage rules from this repo unless explicitly required by ops.

---

*Generated for the TastyKart Flutter customer codebase. Update this file when you add major features, collections, or architecture changes.*
