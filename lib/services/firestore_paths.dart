/// Collection / doc paths shared with TastyKart Admin (`admin.md`).
/// Do **not** invent new top-level collections — admin CRUD + rules own these.
class FirestorePaths {
  FirestorePaths._();

  static const users = 'users';
  static const orders = 'orders';
  static const restaurants = 'restaurants';
  static const restaurantCategories = 'restaurantCategories';
  static const foodCategories = 'foodCategories';
  static const foodItems = 'foodItems';
  static const addons = 'addons';
  static const offers = 'offers';
  static const coupons = 'coupons';
  static const banners = 'banners';
  static const customers = 'customers';
  static const deliveryPartners = 'deliveryPartners';
  static const subscriptions = 'subscriptions';
  static const transactions = 'transactions';
  static const reviews = 'reviews';
  static const notifications = 'notifications';
  static const settings = 'settings';

  /// Single platform settings document written by Admin.
  static const settingsAdminDoc = 'admin';
}
