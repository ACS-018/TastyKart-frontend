# TastyKart Admin — Project Overview & Firebase Guide

Complete reference for the **TastyKart Admin Panel** (`com.arrowcoders.tastycartadmin`): architecture, Firebase config keys, Firestore collections, Storage paths, security rules, restaurant menu hierarchy, and how the app talks to Firebase.

---

## 1. Project overview

**TastyKart** is a food-delivery **admin / ops dashboard** for managing:

- Live orders & dispatch
- Restaurants and **per-restaurant menus** (categories → items → add-ons)
- Customers & delivery partners
- Coupons, offers, banners, subscriptions
- Payments, reviews, notifications
- Analytics reports (PDF / Excel export)
- Platform settings stored in Firestore

| Item | Value |
|------|--------|
| App name | TastyKart Admin |
| Package / npm name | `com.arrowcoders.tastycartadmin` |
| Firebase project | `tastykart-b791a` |
| Hosting URL | https://tastykart-b791a.web.app |
| Stack | React 19 + Vite 8 + TypeScript + Tailwind CSS 4 |
| Backend | Firebase Auth, Firestore, Storage, Analytics, Hosting |
| Brand color | `#B32B2C` |

---

## 2. Tech stack

### Frontend
- **React 19** + **React Router 7** (lazy-loaded pages)
- **Vite 8** + **TypeScript**
- **Tailwind CSS 4** (`@tailwindcss/vite`)
- **Framer Motion**, **Recharts**, **TanStack Table**
- **jsPDF** + **jspdf-autotable** (PDF reports)
- **xlsx** (Excel reports)
- **Lucide React** icons

### Firebase SDK (`firebase` v12)
- `firebase/app` — init
- `firebase/auth` — email/password admin login
- `firebase/firestore` — realtime collections + settings doc
- `firebase/storage` — image uploads
- `firebase/analytics` — optional browser analytics

---

## 3. Repository structure

```
Tasty-Kart/
├── public/                 # favicon, logos, static assets
├── scripts/
│   └── seed-menu.ts        # CLI seed: restaurants + menu → Firestore
├── src/
│   ├── App.tsx             # Routes + providers
│   ├── main.tsx            # React root + ErrorBoundary
│   ├── index.css           # Tailwind + theme
│   ├── pages/              # Feature screens (Dashboard, Restaurants, RestaurantMenu, …)
│   ├── components/
│   │   ├── layout/         # Sidebar, Topbar, Layout
│   │   ├── shared/         # DataTable, ProtectedRoute, …
│   │   └── ui/             # Button, Modal, Toast, Input, …
│   ├── context/            # Auth, Theme, Sidebar
│   ├── data/dummy.ts       # Shared TypeScript types + chart seed arrays
│   └── lib/
│       ├── firebase.ts     # Firebase config + service exports
│       ├── firebaseService.ts  # CRUD, seed, subscriptions, settings, menu helpers
│       ├── reportExport.ts # PDF / Excel export
│       └── utils.ts        # formatCurrency, cn, …
├── firestore.rules         # Firestore security rules
├── storage.rules           # Cloud Storage security rules
├── firestore.indexes.json
├── firebase.json           # Hosting + Firestore + Storage deploy config
├── .firebaserc             # Default project: tastykart-b791a
├── FIREBASE_AND_PROJECT_OVERVIEW.md
└── package.json
```

---

## 4. Firebase web config keys

Configured in `src/lib/firebase.ts` and bound to project **`tastykart-b791a`**.

| Key | Purpose |
|-----|---------|
| `apiKey` | Identifies the Firebase web app to Google APIs |
| `authDomain` | Auth redirect / hosted auth domain (`*.firebaseapp.com`) |
| `projectId` | Firestore / Storage / Hosting project id |
| `storageBucket` | Default Cloud Storage bucket |
| `messagingSenderId` | FCM / messaging (reserved for future push) |
| `appId` | Unique web app id under the Firebase project |
| `measurementId` | Google Analytics measurement id (`G-…`) |

> **Note:** These are *client* config values (required by the Firebase JS SDK). They are not secret by themselves. Real security comes from **Auth + Firestore/Storage rules**. Prefer moving them to Vite env vars (`VITE_FIREBASE_*`) for cleaner environments.

### Services exported from `firebase.ts`

```ts
export const auth     // Firebase Auth
export const db       // Firestore
export const storage  // Cloud Storage
export let analytics  // Analytics (if browser supports it)
```

---

## 5. How Firebase is handled in the app

### 5.1 Layering

| Layer | File | Responsibility |
|-------|------|----------------|
| Init | `src/lib/firebase.ts` | Create app, auth, db, storage, analytics |
| Data API | `src/lib/firebaseService.ts` | Seed, `onSnapshot` subscriptions, CRUD, uploads, admin settings, menu helpers |
| Auth UI state | `src/context/AuthContext.tsx` | Login/logout, ID token, local session cache |
| Pages | `src/pages/*` | Call subscribe/CRUD helpers; render tables & forms |

### 5.2 Realtime reads

Most screens use:

```ts
subscribeToCollection<T>('collectionName', (liveData) => setState(liveData))
```

Special cases:
- **Orders** → `subscribeToOrders()` with `orderBy('createdAt', 'desc')`
- **Admin settings** → `subscribeToAdminSettings()` on doc `settings/admin`
- **Restaurant menu** (`/restaurants/:id`) → filters `foodCategories`, `foodItems`, `addons` by `restaurantId`

### 5.3 Writes (CRUD)

| Helper | Behavior |
|--------|----------|
| `addDocumentToFirestore(collection, data)` | `setDoc` merge with generated or provided `id` |
| `updateDocumentInFirestore(collection, id, data)` | `updateDoc` + `updatedAt` |
| `deleteDocumentFromFirestore(collection, id)` | `deleteDoc` |
| `updateOrderStatusInFirestore(orderId, status)` | Updates order status |
| `createOrUpdateUserProfile(profile)` | Writes `users/{uid}` |
| `saveAdminSettings(settings)` | Writes `settings/admin` |
| `seedDefaultCatalogForRestaurant(restaurant)` | Creates default categories + common add-ons for a new restaurant |
| `buildFoodCategoriesForRestaurant(restaurant)` | Builds category docs (Starters, Main Course, cuisine extras, …) |

### 5.4 Seeding

| Function / command | What it writes |
|--------------------|----------------|
| `seedAllDataToFirebase()` | Full platform seed (orders, customers, partners, menus, coupons, settings, …). Triggered from Dashboard / Quick Actions. |
| `seedRestaurantMenuToFirebase()` | **Restaurants + menu only** (restaurants, foodCategories, foodItems, addons, restaurantCategories). |
| `npm run seed:menu` | CLI runner for `seedRestaurantMenuToFirebase()` via `scripts/seed-menu.ts`. |

Typical seeded menu counts (after `npm run seed:menu`):

| Collection | Approx. count |
|------------|---------------|
| `restaurants` | 8 |
| `foodCategories` | ~39 (per-restaurant, includes Starters) |
| `foodItems` | ~42 (linked via `restaurantId` + `categoryId`) |
| `addons` | ~64 (8 restaurants × 8 add-ons each) |
| `restaurantCategories` | 8 (cuisine types, global) |

### 5.5 Auth flow

1. Email/password via Firebase Auth (`signInWithEmailAndPassword` / auto-create for known admins).
2. `onAuthStateChanged` syncs user into React state.
3. Session cached in **localStorage**:
   - `tastykart_auth_user` — user profile JSON
   - `tastykart_auth_token` — Firebase ID token (or fallback session string)
4. `ProtectedRoute` waits for auth loading, then redirects unauthenticated users to `/login`.

Known admin emails used in role logic (see `AuthContext`):
- `admin123@gmail.com` → Super Admin
- `uday@gmail.com` → Admin (also referenced in Firestore `isAdmin()` rules)

### 5.6 Storage uploads

`uploadImageToStorage(file, folderName)` uploads to:

```
gs://tastykart-b791a.firebasestorage.app/{folderName}/{timestamp}_{safeFileName}
```

Folders used by the UI:

| Folder | Used by |
|--------|---------|
| `restaurants` | Restaurant logos |
| `foodItems` | Food item images |
| `foodCategories` | Food category images |
| `restaurantCategories` | Restaurant category images |
| `banners` | Banner creatives |
| `images` | Default fallback folder |

On upload failure, the helper falls back to a **local data URL** so the UI can still proceed offline/demo.

---

## 6. Restaurant menu data model

Menus are **restaurant-scoped** (not global-only). Hierarchy:

```
Restaurant
  └── Food Categories  (e.g. Starters, Main Course, Desserts, cuisine-specific)
        └── Food Items
  └── Add-ons          (restaurant-level extras; optional foodItemId)
```

### Admin UX

| Action | Where |
|--------|--------|
| List restaurants | `/restaurants` |
| Manage one restaurant’s menu | `/restaurants/:id` (**Manage Menu** / utensils icon) — tabs: Categories · Food Items · Add-ons |
| All categories across kitchens | `/food-categories` |
| All items across kitchens | `/food-items` |
| All add-ons across kitchens | `/addons` |

### Default categories (every restaurant)

Created by `buildFoodCategoriesForRestaurant` / `seedDefaultCatalogForRestaurant`:

1. **Starters**
2. **Main Course**
3. **Desserts & Shakes**
4. **Beverages**
5. Plus cuisine extras when matching (e.g. Burgers & Wraps, Pizzas, Biryani & Rice, Chinese, Seafood, South Indian)

Creating a restaurant in the admin UI also seeds those default categories and a few common add-ons (Extra Cheese, Mineral Water, Soft Drink).

### Doc id patterns

| Entity | Example id |
|--------|------------|
| Restaurant | `res_1` |
| Food category | `cat_res_1_starters` |
| Food item | `food_1` … `food_42` |
| Add-on | `add_res_1_cheese` |

---

## 7. Firestore collections & document keys

All business data lives under the default Firestore database for `tastykart-b791a`.

### 7.1 Collection map

| Collection | Doc id pattern | Primary UI page |
|------------|----------------|-----------------|
| `users` | Firebase Auth `uid` | Auth / profile sync |
| `orders` | e.g. `ORD-1001` | Orders, Dashboard |
| `restaurants` | e.g. `res_1` | Restaurants, Restaurant Menu |
| `restaurantCategories` | e.g. `rcat_1` | Restaurant Categories (cuisine types) |
| `foodCategories` | e.g. `cat_res_1_starters` | Restaurant Menu + Food Categories |
| `foodItems` | e.g. `food_1` | Restaurant Menu + Food Items |
| `addons` | e.g. `add_res_1_cheese` | Restaurant Menu + Add-ons |
| `offers` | e.g. `off_1` | Offers |
| `coupons` | e.g. `c_1` | Coupons |
| `banners` | e.g. `b_1` | Banners |
| `customers` | e.g. `cust_1` | Customers |
| `deliveryPartners` | e.g. `partner_1` | Delivery Partners |
| `subscriptions` | e.g. `sub_1` | Subscriptions |
| `transactions` | e.g. `tx_1` | Payments |
| `reviews` | e.g. `rev_1` | Reviews |
| `notifications` | e.g. `n_1` | Notifications, Topbar |
| `settings` | **`admin`** (single doc) | Settings |

### 7.2 Field keys by collection

#### `users/{uid}`
`uid`, `name`, `email`, `phone?`, `role` (`admin` \| `customer` \| `delivery` \| `restaurant_owner`), `avatar?`, `createdAt?`, `updatedAt`

#### `orders/{orderId}`
`id`, `orderNumber`, `customerId`, `customerName`, `customerPhone`, `restaurantId`, `restaurantName`, `deliveryPartnerId?`, `deliveryPartnerName?`, `status` (`pending` \| `accepted` \| `preparing` \| `picked` \| `delivered` \| `cancelled` \| `refunded`), `paymentMethod`, `items[]` (`name`, `qty`, `price`), `subtotal`, `tax`, `deliveryFee`, `platformFee`, `discount`, `couponCode?`, `total`, `address`, `createdAt`, `timeline[]` (`status`, `time`), `updatedAt?`

#### `restaurants/{id}`
`id`, `name`, `logo?`, `cover?`, `cuisine`, `address`, `city`, `rating`, `totalOrders`, `revenue`, `status`, `owner`, `phone`, `email`, `openingHours`, `deliveryTime`, `minOrder`, `isVeg`, `featured?`, `gst?`, `pan?`, `bankAccount?`, `ifsc?`, `joinedDate?`, `description?`

#### `restaurantCategories/{id}`
Global cuisine-type labels (not per-restaurant menus).  
`id`, `name`, `icon?`, `restaurantCount?`, `status`, optional image / description / sort fields from UI

#### `foodCategories/{id}`
Restaurant-scoped menu sections (e.g. Starters, Main Course).  
`id`, `restaurantId`, `restaurantName`, `name`, `icon?`, `description?`, `image?`, `sortOrder?`, `itemCount?`, `status`

#### `foodItems/{id}`
Food items under a restaurant category.  
`id`, `restaurantId`, `restaurantName`, `categoryId`, `categoryName`, `name`, `image` / `imageUrl`, `price`, `discountedPrice?`, `preparationTime?`, `isVeg`, `status`, `description?`, `ingredients?`, `rating?`, `totalRatings?`, `available?`, `inStock?`, `tags[]?`

#### `addons/{id}`
Add-ons belonging to a restaurant.  
`id`, `restaurantId`, `restaurantName`, `foodItemId?`, `name`, `price`, `category?`, `status`, `description?`

#### `offers/{id}`
`id`, `title` / `name`, `code?`, `minOrder?`, `validTill` / `expiry`, `status`, `description?`, `image?`, `type?`, `discount?`, `restaurantName?`

#### `coupons/{id}`
`id`, `code`, `type` (`percentage` \| `fixed`), `discount`, `minOrder`, `maxDiscount`, `expiry`, `usageCount`, `usageLimit`, `active`, `status`, `description?`

#### `banners/{id}`
`id`, `title`, `imageUrl`, `status`, `link`, `order` / `sortOrder`, `type?`

#### `customers/{id}`
`id`, `name`, `email`, `phone`, `avatar`, `city`, `joinedDate`, `totalOrders`, `totalSpend`, `walletBalance`, `status` (`active` \| `blocked`), `favorites?`, `addresses?`

#### `deliveryPartners/{id}`
`id`, `name`, `phone`, `avatar`, `email`, `vehicle`, `vehicleNumber`, `status`, `currentOrder?`, `rating`, `completedOrders`, `earnings`, `acceptRate`, `rejectRate`, `city`, `joinedDate`, `approved`, `documents?`, `bankAccount?`, `ifsc?`

#### `subscriptions/{id}`
`id`, `name`, `price`, `duration`, `status`, `benefits[]`, `subscriberCount` / `subscribers`, `color?`

#### `transactions/{id}`
`id`, `orderNumber`, `customerName`, `amount`, `method`, `status`, `refunded`, `createdAt`

#### `reviews/{id}`
`id`, `customerName`, `customerId?`, `restaurantName?`, `rating`, `comment`, `type`, `status`, `reply?`, `createdAt`

#### `notifications/{id}`
`id`, `title`, `message`, `type`, `read`, `createdAt`

#### `settings/admin` (platform settings)
Nested object keys:

- **general:** `appName`, `tagline`, `supportEmail`, `supportPhone`, `currency`, `language`, `logoUrl`
- **charges:** `baseDeliveryFee`, `maxDeliveryFee`, `platformFee`, `freeDeliveryThreshold`, `minOrderValue`, `surgeMultiplier`
- **delivery:** `maxRadiusKm`, `avgDeliveryTimeMin`, `partnerCommissionPercent`, `assignmentMode`
- **tax:** `gstRate`, `gstNumber`, `taxAppliedOn`, `taxDisplay`
- **legal:** `terms`, `privacy`, `refund`
- **security:** `twoFactorEnabled`, `loginNotifications`, `sessionTimeoutMin`
- **about:** `aboutUs`, `website`, `contactEmail`, `version`
- plus `updatedAt` on save

### 7.3 TypeScript types

Defined in `src/data/dummy.ts`:

- `Restaurant`
- `FoodCategory` — requires `restaurantId`, `restaurantName`
- `FoodItem` — requires `restaurantId`, `restaurantName`, `categoryId`, `categoryName`
- `Addon` — requires `restaurantId`, `restaurantName`
- `Order`, `Customer`, `DeliveryPartner`, …

---

## 8. Client-side keys (not Firestore)

| Storage | Key | Purpose |
|---------|-----|---------|
| `localStorage` | `tastykart_auth_user` | Cached logged-in user JSON |
| `localStorage` | `tastykart_auth_token` | Cached auth token |
| `localStorage` | `tastykart-theme` | Light / dark theme preference |

---

## 9. Firestore security rules

File: **`firestore.rules`**

### Helper functions
- `isSignedIn()` — `request.auth != null`
- `isAdmin()` — signed-in and (`email == uday@gmail.com` **or** `users/{uid}.role == 'admin'`)
- `isOwner(userId)` — `request.auth.uid == userId`

### Current access matrix

| Path | Read | Write | Notes |
|------|------|-------|-------|
| `users/{userId}` | Signed-in | Owner or admin | Stricter than other collections |
| `orders/{…}` | **Public (`true`)** | **Public** | TODO: lock down |
| `deliveryPartners/{…}` | Public | Public | TODO |
| `restaurants/{…}` | Public | Public | TODO |
| `restaurantCategories/{…}` | Public | Public | TODO |
| `foodItems/{…}` | Public | Public | TODO |
| `foodCategories/{…}` | Public | Public | TODO |
| `addons/{…}` | Public | Public | TODO |
| `coupons/{…}` | Public | Public | TODO |
| `offers/{…}` | Public | Public | TODO |
| `banners/{…}` | Public | Public | TODO |
| `reviews/{…}` | Public | Public | TODO |
| `customers/{…}` | Public | Public | TODO |
| `transactions/{…}` | Public | Public | TODO |
| `subscriptions/{…}` | Public | Public | TODO |
| `notifications/{…}` | Public | Public | TODO |
| `settings/{docId}` | Public | Public | Includes `admin` settings |

### Recommended production hardening
Replace `allow read, write: if true` with admin-only (or role-based) rules, e.g.:

```
allow read, write: if isAdmin();
```

For customer apps, split read/write by ownership (`customerId == request.auth.uid`).

Deploy rules:

```bash
firebase deploy --only firestore:rules
```

---

## 10. Firebase Storage rules

File: **`storage.rules`**

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if true;
    }
  }
}
```

**Meaning today:** any client that can reach the bucket may read/write any path (used for easy admin image uploads during development).

### Recommended production rules (example)

```
match /restaurants/{fileName} {
  allow read: if true;
  allow write: if request.auth != null
               && request.resource.size < 5 * 1024 * 1024
               && request.resource.contentType.matches('image/.*');
}
```

Apply similar constraints per folder (`foodItems`, `banners`, …). Prefer **admin-only write**.

Deploy:

```bash
firebase deploy --only storage
```

---

## 11. App routes (admin UI)

| Path | Page | Notes |
|------|------|--------|
| `/login` | Public login | |
| `/` | Dashboard | Includes full Seed Firebase action |
| `/orders` | Orders | |
| `/restaurants` | Restaurants | **Manage Menu** → `/restaurants/:id` |
| `/restaurants/:id` | **Restaurant Menu** | Categories → Items → Add-ons for one restaurant |
| `/restaurant-categories` | Restaurant categories | Global cuisine types |
| `/food-categories` | Food categories | All restaurants; requires `restaurantId` on save |
| `/food-items` | Food items | All restaurants; requires restaurant + category |
| `/addons` | Add-ons | All restaurants; requires `restaurantId` |
| `/offers` | Offers | |
| `/coupons` | Coupons | |
| `/banners` | Banners | |
| `/customers` | Customers | |
| `/delivery-partners` | Delivery partners | |
| `/subscriptions` | Subscriptions | |
| `/payments` | Payments / transactions | |
| `/reviews` | Reviews | |
| `/notifications` | Notifications | |
| `/reports` | Analytics + PDF/Excel export | |
| `/settings` | Platform settings → Firestore `settings/admin` | |
| `/profile` | Admin profile UI | |

Unknown routes redirect to `/login`. Authenticated area is wrapped by `ProtectedRoute` + `Layout` (Sidebar + Topbar).

---

## 12. Local development & deploy

### Scripts

```bash
npm install
npm run dev        # Vite → http://localhost:5173
npm run build      # tsc + vite build → dist/
npm run preview    # preview production build
npm run lint       # oxlint
npm run seed:menu  # Push restaurant + menu dummy data to Firestore
```

### Firebase deploy targets (`firebase.json`)

```bash
# Hosting (SPA from dist/)
firebase deploy --only hosting

# Firestore rules (+ indexes if needed)
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes

# Storage rules
firebase deploy --only storage

# Combined
firebase deploy --only hosting,firestore:rules,storage
```

Default project (`.firebaserc`): **`tastykart-b791a`**.

---

## 13. Data flow (high level)

```
┌─────────────┐     Auth (email/password)      ┌──────────────────┐
│  Login UI   │ ─────────────────────────────► │ Firebase Auth    │
└─────────────┘                                └────────┬─────────┘
                                                       │
┌─────────────┐   onSnapshot / setDoc / updateDoc      ▼
│ Admin Pages │ ◄────────────────────────────────► Firestore
│ Restaurant  │     restaurants
│ Menu (:id)  │       ├── foodCategories (restaurantId)
│             │       ├── foodItems      (restaurantId + categoryId)
│             │       └── addons         (restaurantId)
└──────┬──────┘                                (+ settings/admin)
       │
       │ uploadBytes / getDownloadURL
       ▼
  Cloud Storage  (restaurants/, foodItems/, banners/, …)
```

---

## 14. Security checklist before production

- [ ] Restrict Firestore rules (remove public `read, write: if true`)
- [ ] Restrict Storage rules (auth + content-type + size limits)
- [ ] Move Firebase web config to env vars; rotate keys if ever leaked with open rules
- [ ] Enforce admin claims / `users.role == 'admin'` for all admin writes
- [ ] Remove or gate seed button / `npm run seed:menu` in production builds
- [ ] Review hardcoded admin emails in Auth + rules
- [ ] Enable App Check for abuse protection

---

## 15. Related files (quick index)

| Topic | Path |
|-------|------|
| Firebase init & config keys | `src/lib/firebase.ts` |
| Collections CRUD / seed / settings / menu helpers | `src/lib/firebaseService.ts` |
| CLI menu seed | `scripts/seed-menu.ts` |
| Auth session | `src/context/AuthContext.tsx` |
| Types (`Restaurant`, `FoodCategory`, `FoodItem`, `Addon`, …) | `src/data/dummy.ts` |
| Restaurant list | `src/pages/Restaurants.tsx` |
| Per-restaurant menu UI | `src/pages/RestaurantMenu.tsx` |
| Firestore rules | `firestore.rules` |
| Storage rules | `storage.rules` |
| Deploy config | `firebase.json`, `.firebaserc` |
| PDF / Excel reports | `src/lib/reportExport.ts` |
| Routes | `src/App.tsx` |

---

*Keep this document updated when collections, menu hierarchy, rules, seed scripts, or config keys change.*
