# Tasty Kart — Project Overview & Firebase Guide

Complete reference for the **Tasty Kart** Flutter food-delivery app.

> **Admin pairing:** This app shares Firebase project `tastykart-b791a` with TastyKart Admin.  
> Integration details + **no Admin rules changes**: see [`CUSTOMER_ADMIN_INTEGRATION.md`](./CUSTOMER_ADMIN_INTEGRATION.md) and [`admin.md`](./admin.md).

---

## 1. Project overview

| Item | Detail |
|------|--------|
| **App name** | Tasty Kart |
| **Stack** | Flutter (SDK `^3.9.2`) + Firebase |
| **Firebase project** | `tastykart-b791a` (from Console) |
| **Primary color** | `#B32B2C` (`AppColors.primary`) |
| **Entry** | `lib/main.dart` → `Firebase.initializeApp()` → `HomeScreen` inside `CartScope` |

### What the app does

Tasty Kart is a food ordering client that:

1. Loads **banners** and **food items** live from Cloud Firestore  
2. Lets users browse categories, restaurant menus, add-ons, and cart  
3. Walks through **checkout** (address → payment → track → delivered → rate)  
4. Exposes **Profile**, **Favourites**, **Order History**, **Settings**, **Notifications**, **Select Location**

Cart / checkout / profile UI is mostly **local state** today. Catalog data (**banners**, **foodItems**) is **Firestore-backed**.

---

## 2. Firebase packages in use

From `pubspec.yaml`:

| Package | Purpose | Status in app |
|---------|---------|---------------|
| `firebase_core` | Initialize Firebase | Wired in `main.dart` |
| `cloud_firestore` | Read banners & food items | Wired (streams / queries) |
| `firebase_auth` | Login / signup | Dependency present; **auth screens not yet calling Auth APIs** |

**Not yet added (recommended later):**

| Package | Purpose |
|---------|---------|
| `firebase_storage` | Upload profile / food images |
| `cloud_functions` | Secure payments / order creation |
| `firebase_messaging` | Push notifications |

---

## 3. How Firebase is handled in code

### 3.1 Initialization

```dart
// lib/main.dart
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp();
runApp(const TastyKartApp());
```

Uses platform default options (Android `google-services.json` / iOS `GoogleService-Info.plist`).

### 3.2 Live reads (StreamBuilder pattern)

| Screen / widget | Collection | Query |
|-----------------|------------|--------|
| `banner_carousel.dart` | `banners` | `status == 'active'` |
| `restaurant_grid.dart` | `foodItems` | `status == 'active'` **and** `available == true` |
| `featured_list.dart` | `foodItems` | same as grid |
| `favorites_screen.dart` | `foodItems` | `status == 'active'` (UI favourites; not a separate collection yet) |
| `category_screen.dart` | `foodItems` | `status == 'active'`, then client filter by category / tags |
| `restaurant_menu_screen.dart` | `foodItems` | `status == 'active'`, then filter by `restaurantName` |

Models:

- Banner fields parsed inline in `banner_carousel.dart`  
- Food fields mapped in `lib/models/food_item.dart` → `FoodItem.fromDoc`

### 3.3 Local-only (not written to Firebase yet)

| Feature | Location |
|---------|----------|
| Cart lines, qty, add-ons | `lib/state/cart_controller.dart` |
| Selected delivery address | `CartController.selectedAddress` |
| Checkout / payment / track UI | `lib/screens/checkout/` |
| Order history sample cards | Hardcoded in `order_history_screen.dart` |
| Notifications list | Hardcoded in `notifications_screen.dart` |

### 3.4 Auth screens (UI only for now)

Under `lib/screens/auth/`: Login, Signup, OTP, Forgot / Reset password.  
`main.dart` currently opens **Home** directly — wire Auth when ready.

---

## 4. Firestore collections & field keys

Collections visible / used with this project (Console + app):

```
banners
coupons
customers
deliveryPartners
foodItems          ← used heavily
offers
orders
restaurants
subscriptions
users
```

### 4.1 `banners` — **USED**

Document IDs example: `b_1`, `b_2`, `banner_<timestamp>`

| Key | Type | Example | App usage |
|-----|------|---------|-----------|
| `id` | string | `"b_1"` | Identity |
| `title` | string | `"Weekend Feast 50% OFF"` | Overlay title |
| `imageUrl` | string | Unsplash / Storage URL | `Image.network` |
| `status` | string | `"active"` / `"inactive"` | Filter |

**App query:**

```text
banners.where('status', isEqualTo: 'active')
```

---

### 4.2 `foodItems` — **USED**

Document IDs example: `food_1`, `food_2`, `food_<timestamp>`

| Key | Type | Example | App usage |
|-----|------|---------|-----------|
| `id` | string | `"food_1"` | Identity |
| `name` | string | `"Butter Chicken Special"` | Title |
| `description` | string | gravy text | Menu / cards |
| `image` | string | URL | Fallback image |
| `imageUrl` | string | URL | Preferred image (`imageUrl` \|\| `image`) |
| `categoryName` | string | `"Main Course"` | Category / cuisine |
| `restaurantName` | string | `"Spice Garden"` | Menu grouping |
| `price` | number (int) | `340` | MRP |
| `discountedPrice` | number (int) | `290` | Selling price |
| `preparationTime` | number (int) | `25` | “25 Min” |
| `rating` | number (double) | `4.9` | Stars |
| `totalRatings` | number (int) | `340` | Count |
| `isVeg` | boolean | `false` | Veg / non-veg filter |
| `available` | boolean | `true` | Grid / featured filter |
| `inStock` | boolean | `true` | Stock flag |
| `status` | string | `"active"` | Must be active to show |
| `ingredients` | string | `"Chicken, Butter, …"` | Detail (optional in UI) |
| `tags` | array\<string\> | `["nonveg","bestseller","main course"]` | Badges / filters |
| `variants` | array\<map\> | see below | Portion sizes |

**Variant map keys:**

| Key | Type | Example |
|-----|------|---------|
| `name` | string | `"Half (500ml)"` |
| `price` | number | `180` |

**App queries:**

```text
foodItems.where('status', isEqualTo: 'active')
foodItems.where('status', isEqualTo: 'active').where('available', isEqualTo: true)
```

---

### 4.3 `restaurants` — Console present / recommended schema

| Key | Type | Notes |
|-----|------|--------|
| `id` | string | Doc id |
| `name` | string | Matches `foodItems.restaurantName` |
| `imageUrl` | string | Cover |
| `cuisines` | array\<string\> | e.g. North Indian, Biryani |
| `rating` | number | Aggregate |
| `deliveryTimeMin` | number | Minutes |
| `deliveryTimeMax` | number | Minutes |
| `location` | string | Area name |
| `address` | string | Full address |
| `status` | string | `active` / `inactive` |
| `isVegOnly` | boolean | Optional |

---

### 4.4 `orders` — recommended for checkout persistence

| Key | Type | Notes |
|-----|------|--------|
| `id` | string | e.g. `ORD1002` |
| `userId` | string | Auth uid |
| `restaurantName` | string | |
| `items` | array\<map\> | `{ foodId, name, qty, price, addons[] }` |
| `itemsTotal` | number | |
| `deliveryFee` | number | |
| `taxes` | number | |
| `packingCharges` | number | |
| `discount` | number | |
| `grandTotal` | number | |
| `paymentMethod` | string | `upi` / `card` / `cod` |
| `paymentStatus` | string | `pending` / `paid` / `failed` |
| `orderStatus` | string | `placed` / `preparing` / `out_for_delivery` / `delivered` / `cancelled` |
| `deliveryAddress` | map | `{ label, fullAddress, lat, lng }` |
| `riderId` | string | Optional link to `deliveryPartners` |
| `createdAt` | timestamp | |
| `updatedAt` | timestamp | |

---

### 4.5 `users` / `customers` — recommended for profile

| Key | Type | Notes |
|-----|------|--------|
| `uid` | string | Firebase Auth uid |
| `name` | string | |
| `email` | string | |
| `phone` | string | |
| `bio` | string | Edit profile |
| `photoUrl` | string | Storage URL |
| `vegMode` | boolean | |
| `favouriteFoodIds` | array\<string\> | Real favourites |
| `addresses` | array\<map\> | Saved locations |
| `createdAt` | timestamp | |

**Address map keys:** `label`, `fullAddress`, `lat`, `lng`, `isDefault`

---

### 4.6 `deliveryPartners`

| Key | Type | Notes |
|-----|------|--------|
| `id` | string | |
| `name` | string | e.g. Ramesh |
| `phone` | string | |
| `photoUrl` | string | |
| `rating` | number | |
| `ordersDelivered` | number | |
| `status` | string | `available` / `busy` / `offline` |

---

### 4.7 `coupons` / `offers`

| Key | Type | Notes |
|-----|------|--------|
| `id` | string | |
| `code` | string | Coupon code |
| `title` | string | |
| `description` | string | |
| `discountType` | string | `percent` / `flat` |
| `discountValue` | number | |
| `minOrder` | number | |
| `status` | string | `active` |
| `validUntil` | timestamp | |

---

### 4.8 `subscriptions`

| Key | Type | Notes |
|-----|------|--------|
| `id` | string | |
| `userId` | string | |
| `planName` | string | e.g. Tasty Cart |
| `price` | number | `49` |
| `benefits` | array\<string\> | Free delivery, etc. |
| `status` | string | `active` / `expired` |
| `startsAt` | timestamp | |
| `endsAt` | timestamp | |

---

## 5. Composite indexes (Firestore)

Create these if Console asks after deploying queries:

1. **foodItems**  
   - `status` Asc → `available` Asc  
2. **foodItems** (optional later)  
   - `status` Asc → `restaurantName` Asc  
3. **banners**  
   - usually single-field `status` is enough  

---

## 6. Firestore security rules

Paste into **Firebase Console → Firestore → Rules** (adjust before production).

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }

    function isAdmin() {
      return isSignedIn()
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    // Public catalog — read-only for clients
    match /banners/{bannerId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /foodItems/{foodId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /restaurants/{restaurantId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /offers/{offerId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /coupons/{couponId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    // User profile
    match /users/{userId} {
      allow read: if isOwner(userId) || isAdmin();
      allow create: if isOwner(userId);
      allow update: if isOwner(userId) || isAdmin();
      allow delete: if isAdmin();
    }

    match /customers/{customerId} {
      allow read, write: if isOwner(customerId) || isAdmin();
    }

    // Orders — users create/read own; status updates preferably via Admin / Cloud Functions
    match /orders/{orderId} {
      allow read: if isSignedIn()
        && (resource.data.userId == request.auth.uid || isAdmin());
      allow create: if isSignedIn()
        && request.resource.data.userId == request.auth.uid;
      allow update: if isAdmin()
        || (isSignedIn()
            && resource.data.userId == request.auth.uid
            && request.resource.data.diff(resource.data).affectedKeys()
                .hasOnly(['orderStatus', 'updatedAt']));
      allow delete: if isAdmin();
    }

    match /subscriptions/{subId} {
      allow read: if isSignedIn()
        && (resource.data.userId == request.auth.uid || isAdmin());
      allow write: if isAdmin();
    }

    match /deliveryPartners/{partnerId} {
      allow read: if isSignedIn();
      allow write: if isAdmin();
    }
  }
}
```

> **Dev tip:** While prototyping you may temporarily use `allow read, write: if true;` — **never ship that**.

---

## 7. Firebase Storage rules (Firestorage)

Use when you add `firebase_storage` for profile photos, restaurant images, etc.

Suggested folder layout:

```text
gs://tastykart-b791a.appspot.com/
  banners/{bannerId}.jpg
  foodItems/{foodId}.jpg
  restaurants/{restaurantId}.jpg
  users/{uid}/profile.jpg
  riders/{riderId}.jpg
```

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    function isSignedIn() {
      return request.auth != null;
    }

    function isImage() {
      return request.resource.contentType.matches('image/.*');
    }

    function under5MB() {
      return request.resource.size < 5 * 1024 * 1024;
    }

    // Public catalog images — readable by all; writable by admins via Console / Admin SDK
    match /banners/{fileName} {
      allow read: if true;
      allow write: if false; // upload from admin tools only
    }

    match /foodItems/{fileName} {
      allow read: if true;
      allow write: if false;
    }

    match /restaurants/{fileName} {
      allow read: if true;
      allow write: if false;
    }

    // User profile photo
    match /users/{userId}/{fileName} {
      allow read: if true;
      allow write: if isSignedIn()
        && request.auth.uid == userId
        && isImage()
        && under5MB();
    }

    match /riders/{fileName} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

Store the resulting download URL in Firestore as `imageUrl` / `photoUrl`.

---

## 8. App architecture & folder map

```text
lib/
├── main.dart                 # Firebase init + CartScope + MaterialApp
├── constants/                # colors, images
├── models/
│   └── food_item.dart        # FoodItem.fromDoc
├── state/
│   └── cart_controller.dart  # Cart + address (local)
├── utils/
│   └── responsive.dart
├── global_widgets/           # buttons, text fields, loading
└── screens/
    ├── Home/                 # Home tab + components (banners, grid, filters…)
    ├── category/             # Category discovery (e.g. Biryani)
    ├── restaurant/           # Menu + add-ons sheet
    ├── checkout/             # Cart, payment, card, track
    ├── location/             # Select Location screen
    ├── notifications/        # Notifications list
    ├── order/                # Delivered + Rate & Review
    ├── profile/              # Profile, edit, favourites, orders, settings
    └── auth/                 # Login / signup UI (Auth wiring pending)
```

### Navigation flow (high level)

```text
Home
 ├─ Explore chip → Category → Restaurant Menu → Add-ons → Cart bar
 ├─ Food / Featured card → Restaurant Menu
 ├─ Location bar → Select Location
 ├─ Bell → Notifications
 └─ Bottom nav
      ├─ Home
      ├─ Orders (Order History)
      ├─ Favourites
      └─ Profile → Edit / Settings / Favourites / Orders

Checkout:
  Cart Summary → Select Location → Payment → Card (optional)
       → Track Order → Delivered → Rate & Review → Home
```

---

## 9. Screen checklist vs Firebase

| Screen | Data source today |
|--------|-------------------|
| Banner carousel | Firestore `banners` |
| Restaurant grid / featured / menu / category / favourites | Firestore `foodItems` |
| Cart / payment / track / delivered / rate | Local UI |
| Order history / notifications | Mock / hardcoded |
| Profile / edit / settings / location | Local UI |
| Auth screens | UI only |

---

## 10. Recommended next Firebase work

1. Wire **Firebase Auth** to login/signup; set `home` based on `authStateChanges`.  
2. On signup, create `users/{uid}` with profile keys above.  
3. Persist **orders** on “Pay Now / Make Payment”.  
4. Store real **favourites** on `users.favouriteFoodIds`.  
5. Add **Storage** + `imageUrl` upload for admin / user photos.  
6. Move payment confirmation to **Cloud Functions** (never trust client totals alone).  
7. Use **FCM** to power the Notifications screen.

---

## 11. Quick field cheat-sheet (keys the Flutter app reads today)

### `banners`
`id`, `title`, `imageUrl`, `status`

### `foodItems`
`id`, `name`, `description`, `image`, `imageUrl`, `categoryName`, `restaurantName`, `price`, `discountedPrice`, `preparationTime`, `rating`, `totalRatings`, `isVeg`, `available`, `inStock`, `status`, `ingredients`, `tags[]`, `variants[].name`, `variants[].price`

---

*Last updated for the Tasty Kart Flutter codebase in this repo. Keep this file in sync when you add collections or change queries.*
