import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/checkout/order_chat_screen.dart';
import '../screens/checkout/track_order_screen.dart';
import '../utils/app_navigation.dart';

/// Top-level background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

/// FCM service for the TastyKart customer app.
/// Stores the device token under `customers/{uid}.fcmTokens[]`.
class UserFCMService {
  UserFCMService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'tasty_kart_general';
  static const _channelName = 'TastyKart Notifications';

  // ── Initialise ─────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    // 1. Register background handler.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Request permission (iOS / Android 13+).
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // 3. Create Android notification channel.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Order updates and promotions from TastyKart',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // 4. Initialise flutter_local_notifications with tap handler.
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // 5. Get & save token.
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }

    // 6. Refresh token listener.
    _messaging.onTokenRefresh.listen(_saveToken);

    // 7. Foreground messages — show local notification.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null) {
        _showLocal(
          title: notification.title ?? 'TastyKart',
          body: notification.body ?? '',
          payload: jsonEncode(message.data),
        );
      }
    });

    // 8. Background → foreground tap (app was in background, user tapped).
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessage);

    // 9. Terminated → foreground tap (app was killed, user tapped notification).
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Slight delay ensures the navigator is mounted before we push.
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleRemoteMessage(initial);
      });
    }

    debugPrint('[FCM] UserFCMService initialized');
  }

  // ── Navigation helpers ─────────────────────────────────────────────────────

  /// Handles taps on FCM notifications received while app is in background
  /// or terminated state.
  static void _handleRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final action = data['action']?.toString() ?? '';
    final orderId = _extractOrderId(data);

    if (action == 'open_order_chat' && orderId != null) {
      _navigateToOrderChat(orderId);
    } else if (orderId != null) {
      _navigateToOrder(orderId);
    }
  }

  /// Handles taps on local notifications shown in the foreground.
  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final action = data['action']?.toString() ?? '';
      final orderId = _extractOrderId(data);

      if (action == 'open_order_chat' && orderId != null) {
        _navigateToOrderChat(orderId);
      } else if (orderId != null) {
        _navigateToOrder(orderId);
      }
    } catch (_) {}
  }

  /// Extracts orderId from an FCM data payload.
  /// Checks common field names sent by the server.
  static String? _extractOrderId(Map<String, dynamic> data) {
    for (final key in ['orderId', 'order_id', 'id']) {
      final val = data[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return null;
  }

  /// Navigates to [TrackOrderScreen] using the root navigator key.
  static void _navigateToOrder(String orderId) {
    final nav = AppNavigation.rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: orderId)),
    );
  }

  /// Navigates to the order chat: pushes [TrackOrderScreen] then
  /// [OrderChatScreen] on top so the user can go back to tracking.
  ///
  /// A short delay is inserted between the two pushes so that
  /// [TrackOrderScreen] has time to load the order and resolve the
  /// delivery partner's name before the chat screen is shown.
  static void _navigateToOrderChat(String orderId) {
    final nav = AppNavigation.rootNavigatorKey.currentState;
    if (nav == null) return;
    // First push TrackOrderScreen so the back-stack is correct.
    nav.push(
      MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: orderId)),
    );
    // Then push OrderChatScreen on top after a brief settle delay.
    Future.delayed(const Duration(milliseconds: 600), () {
      final nav2 = AppNavigation.rootNavigatorKey.currentState;
      if (nav2 == null) return;
      nav2.push(
        MaterialPageRoute(
          builder: (_) => OrderChatScreen(
            orderId: orderId,
            partnerName:
                '', // TrackOrderScreen is underneath; partner name loads from there
          ),
        ),
      );
    });
  }

  // ── Token management ───────────────────────────────────────────────────────

  static Future<void> _saveToken(String token) async {
    try {
      // Store locally for quick access.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_fcm_token', token);

      // Store under customers/{uid}.fcmTokens array (append-only, no dupes).
      // Also mark loggedIn:true so the admin panel knows this user is active.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('customers').doc(uid).set({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'loggedIn': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[FCM] Token saved for user $uid');
      }
    } catch (e) {
      debugPrint('[FCM] Error saving token: $e');
    }
  }

  /// Call on logout to clean up the token from Firestore.
  static Future<void> removeToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('user_fcm_token');
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid != null) {
        final update = <String, dynamic>{
          'loggedIn': false,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (token != null) {
          update['fcmTokens'] = FieldValue.arrayRemove([token]);
        }
        await FirebaseFirestore.instance
            .collection('customers')
            .doc(uid)
            .update(update);
      }
      await prefs.remove('user_fcm_token');
    } catch (e) {
      debugPrint('[FCM] Error removing token: $e');
    }
  }

  // ── Local notification display ─────────────────────────────────────────────

  static Future<void> _showLocal({
    required String title,
    required String body,
    required String payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }
}
