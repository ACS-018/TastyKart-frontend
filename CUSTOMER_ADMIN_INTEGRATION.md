# Customer ↔ Admin Firebase Integration

How the **Flutter customer app** (`tasty_kart`) shares the same Firebase project as **TastyKart Admin** (`admin.md`) **without changing Admin security rules**.

---

## Hard rule

| Do | Do not |
|----|--------|
| Read/write **existing** Admin collections with Admin field keys | Create new top-level collections |
| Keep Admin `firestore.rules` / `storage.rules` as-is | Deploy rule changes from this Flutter repo |
| Treat `settings/admin` as **read-only** | Overwrite Admin settings / seed data |
| Create `orders` / `reviews` with Admin-compatible payloads | Change Admin `isAdmin()` / email-based access |

Shared Firebase project: **`tastykart-b791a`**.

---

## Collections used by customer app

| Collection | Customer access | Wired UI |
|------------|-----------------|----------|
| `banners` | Read `status == active` | Home carousel |
| `foodItems` | Read active (+ available) | Grid, featured, menu, category, favourites |
| `foodCategories` | Read active | Home Explore |
| `addons` | Read | Add-ons sheet |
| `notifications` | Read | Notifications screen |
| `settings/admin` | **Read only** | Delivery fee / tax / platform fee |
| `orders` | **Create** on Pay Now; read for history | Checkout → Admin Orders |
| `reviews` | **Create** on Submit Review | Rate & Review → Admin Reviews |

Admin continues to own CRUD for restaurants, coupons, offers, partners, subscriptions, transactions, etc.

---

## Order payload (must match Admin)

On **Pay Now** / card payment the app writes:

```
id, orderNumber, customerId, customerName, customerPhone,
restaurantName, status: "pending", paymentMethod,
items[{ name, qty, price }],
subtotal, tax, deliveryFee, platformFee, discount, total,
address, timeline[{ status, time }], createdAt, updatedAt
```

Admin Orders page will pick these up via its existing `subscribeToOrders()`.

---

## Flutter service layer

```
lib/services/firestore_paths.dart   # same collection names as admin.md
lib/services/firestore_service.dart # streams + createOrder / addReview
lib/models/admin_models.dart        # FoodCategory, Addon, Notification, Order, Charges
```

---

## Rules note

Current Admin rules (see `admin.md` §8) allow public read/write on catalog + orders during development. The customer app relies on that **as deployed by Admin**.

When Admin hardens rules later:

1. Keep **public read** on `banners`, `foodItems`, `foodCategories`, `addons`, `offers`, `coupons`, `restaurants`
2. Require Auth for `orders` create (`customerId == request.auth.uid`)
3. Keep `settings/{doc}` writable **admin-only**; readable by customers
4. Do **not** require this Flutter repo to ship `firestore.rules`

---

## What Admin can change safely for the customer app

- Banner / food / category / addon content in Console or Admin UI  
- `settings/admin` → `charges.*` and `tax.gstRate` (customer cart fees update live)  
- Order `status` transitions (`pending` → … → `delivered`)

Customer app will reflect those without any Admin rule edits.
