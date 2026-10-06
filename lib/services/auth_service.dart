import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/customer_account.dart';
import 'customer_account_service.dart';
import 'fcm_service.dart';
import 'firestore_paths.dart';

/// Customer Auth — Firebase Auth + Firestore profile sync.
/// Does not modify Admin security rules. Customer `role` is always `customer`.
class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Web OAuth client ID (client_type: 3) from google-services.json.
  /// Required so Google Sign-In returns an idToken for Firebase Auth.
  /// The Android client (client_type: 1) with the SHA-1 is in google-services.json
  /// under com.arrowcoders.foodapp — client_id ending in ...flgiunb.
  ///
  /// NOTE: serverClientId is NOT passed to GoogleSignIn() constructor.
  /// google_sign_in_android v6+ auto-reads default_web_client_id from the
  /// compiled google-services.json resource. Passing it explicitly caused
  /// a conflict that triggered DEVELOPER_ERROR on some builds.

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
    // Do NOT set serverClientId here — the plugin reads default_web_client_id
    // from the compiled google-services.json automatically on Android.
    // Setting it explicitly conflicts with the auto-resolved value and can
    // cause DEVELOPER_ERROR (code 10) even when SHA-1 is correctly registered.
  );

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  // ── Email / password ─────────────────────────────────────────────────────

  static Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // Check Admin block before creating/mirroring customers/{uid}.
    await _enforceNotBlocked(cred.user);
    await ensureCustomerProfile(cred.user);
    return cred;
  }

  static Future<UserCredential> signup({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final trimmedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (!_isValidEmail(normalizedEmail)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address',
      );
    }

    final cred = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      try {
        await user.updateDisplayName(trimmedName);
        await user.reload();
      } catch (_) {}
      try {
        await _writeCustomerDocs(
          user: _auth.currentUser ?? user,
          name: trimmedName.isNotEmpty
              ? trimmedName
              : (normalizedEmail.split('@').first),
          email: normalizedEmail,
          phone: phone,
        );
      } catch (_) {
        // Auth account is created; profile sync can retry on next login.
      }
      // Block check after profile write (new signup docs start as active).
      await _enforceNotBlocked(_auth.currentUser ?? user);
    }
    return cred;
  }

  /// Official Firebase Auth password-reset email.
  ///
  /// Never stores passwords/tokens in Firestore. For email-enumeration
  /// protection, unknown emails are treated as success (same UX as known emails).
  static Future<void> sendPasswordResetEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !_isValidEmail(normalized)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address',
      );
    }

    try {
      await _auth.sendPasswordResetEmail(email: normalized);
    } on FirebaseAuthException catch (e) {
      // Do not reveal whether the email is registered.
      if (e.code == 'user-not-found') return;
      rethrow;
    }
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  /// Update password for the currently signed-in user.
  static Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'Please sign in again to change your password.',
      );
    }
    await user.updatePassword(newPassword);
  }

  // ── Google ───────────────────────────────────────────────────────────────

  static Future<UserCredential> signInWithGoogle() async {
    try {
      // Sign out first so the account picker always appears.
      // This prevents "sign-in cancelled" when a stale token is silently reused
      // and then rejected by Firebase because no SHA-1 is registered.
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the account picker.
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Google sign-in was cancelled.',
        );
      }

      late GoogleSignInAuthentication googleAuth;
      try {
        googleAuth = await googleUser.authentication;
      } on PlatformException catch (e) {
        if (e.code == '10' ||
            (e.message ?? '').contains('DEVELOPER_ERROR') ||
            (e.message ?? '').contains('10:')) {
          throw FirebaseAuthException(
            code: 'google-sign-in-config',
            message:
                'Google Sign-In setup error (DEVELOPER_ERROR).\n'
                'Ensure google-services.json is up to date and '
                'flutter clean has been run.',
          );
        }
        rethrow;
      }

      if (googleAuth.idToken == null) {
        throw FirebaseAuthException(
          code: 'google-missing-id-token',
          message:
              'Google Sign-In did not return an ID token. '
              'Run flutter clean and try again. If the issue persists, '
              'verify the SHA-1 is registered in Firebase Console.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _auth.signInWithCredential(credential);
      await _enforceNotBlocked(cred.user);
      await ensureCustomerProfile(
        cred.user,
        fallbackName: googleUser.displayName,
      );
      return cred;
    } on FirebaseAuthException {
      rethrow;
    } on PlatformException catch (e) {
      final code = e.code;
      final msg = e.message ?? '';

      if (code == '10' ||
          msg.contains('DEVELOPER_ERROR') ||
          code == 'sign_in_failed') {
        throw FirebaseAuthException(
          code: 'google-sign-in-config',
          message:
              'Google Sign-In configuration error. '
              'Run flutter clean and rebuild. '
              'If the issue persists, verify SHA-1 in Firebase Console.',
        );
      }

      // network_error on emulator / no Play Services.
      if (code == 'network_error' || msg.contains('network_error')) {
        throw FirebaseAuthException(
          code: 'network-request-failed',
          message:
              'Network error during Google Sign-In. '
              'Check your internet connection. '
              'On an emulator, ensure Google Play Services is installed.',
        );
      }

      throw FirebaseAuthException(
        code: code,
        message: msg.isNotEmpty ? msg : 'Google sign-in failed.',
      );
    }
  }

  // ── Phone OTP (Firebase Phone Auth) ──────────────────────────────────────

  static Future<void> verifyPhoneNumber({
    required String phoneE164,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      timeout: timeout,
      verificationCompleted: (credential) async {
        if (onAutoVerified != null) {
          onAutoVerified(credential);
        } else {
          await _auth.signInWithCredential(credential);
          await _enforceNotBlocked(_auth.currentUser);
          await ensureCustomerProfile(_auth.currentUser);
        }
      },
      verificationFailed: onError,
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  static Future<UserCredential> signInWithCredential(
    AuthCredential credential,
  ) async {
    final cred = await _auth.signInWithCredential(credential);
    await _enforceNotBlocked(cred.user);
    await ensureCustomerProfile(cred.user);
    return cred;
  }

  static Future<UserCredential> confirmPhoneOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return signInWithCredential(credential);
  }

  // ── Session ──────────────────────────────────────────────────────────────

  /// Signs out Firebase Auth (and Google if used). Always clears the Firebase
  /// session even if Google sign-out fails or hangs.
  /// Also removes the FCM token from Firestore so logged-out users no longer
  /// receive push notifications.
  static Future<void> logout() async {
    // Remove FCM token & set loggedIn:false before signing out so the uid is
    // still available to build the Firestore document reference.
    try {
      await UserFCMService.removeToken();
    } catch (_) {}
    try {
      await _googleSignIn.signOut().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await _googleSignIn.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await _auth.signOut();
  }

  /// If Admin blocked this customer, sign out and throw.
  static Future<void> _enforceNotBlocked(User? user) async {
    if (user == null) return;
    try {
      await CustomerAccountService.assertNotBlocked(user);
    } on CustomerBlockedException {
      await logout();
      rethrow;
    }
  }

  /// Public re-check for AuthGate / checkout / app resume.
  static Future<CustomerAccount?> enforceCustomerAccess(User user) async {
    try {
      return await CustomerAccountService.assertNotBlocked(user);
    } on CustomerBlockedException {
      await logout();
      rethrow;
    }
  }

  // ── Profile sync (Admin-compatible `users` + `customers`) ────────────────

  static Future<void> ensureCustomerProfile(
    User? user, {
    String? fallbackName,
  }) async {
    if (user == null) return;
    final name = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : (fallbackName?.trim().isNotEmpty == true
              ? fallbackName!.trim()
              : (user.email?.split('@').first ?? 'Customer'));
    await _writeCustomerDocs(
      user: user,
      name: name,
      email: user.email ?? '',
      phone: user.phoneNumber,
    );
  }

  static Future<void> _writeCustomerDocs({
    required User user,
    required String name,
    required String email,
    String? phone,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _db.collection(FirestorePaths.users).doc(user.uid).set({
      'uid': user.uid,
      'name': name,
      'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'role': 'customer',
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));

    // Mirror into Admin `customers`. Never overwrite Admin block fields.
    final customerRef = _db.collection(FirestorePaths.customers).doc(user.uid);
    final existing = await customerRef.get();
    final payload = <String, dynamic>{
      'id': user.uid,
      'uid': user.uid,
      'name': name,
      'email': email.trim().toLowerCase(),
      'phone': phone ?? '',
      'updatedAt': now,
    };
    if (!existing.exists) {
      payload['status'] = 'active';
      payload['blockedAt'] = null;
      payload['blockedReason'] = null;
      payload['createdAt'] = now;
    }
    await customerRef.set(payload, SetOptions(merge: true));
  }

  // ── Errors ───────────────────────────────────────────────────────────────

  static String messageFromError(Object error) {
    if (error is CustomerBlockedException) {
      return error.message;
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Enter a valid email address';
        case 'user-disabled':
          return 'This account has been disabled';
        case 'user-not-found':
          return 'No account found for this email';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Invalid email or password';
        case 'email-already-in-use':
          return 'An account already exists for this email';
        case 'weak-password':
          return 'Password is too weak (min 6 characters)';
        case 'too-many-requests':
          return 'Too many attempts. Try again later';
        case 'network-request-failed':
          return 'Network error. Check your connection';
        case 'aborted-by-user':
          return 'Sign-in cancelled';
        case 'operation-not-allowed':
          return 'This sign-in method is not enabled. Use email instead, or enable it in Firebase Console → Authentication → Sign-in method.';
        case 'google-sign-in-config':
        case 'google-missing-id-token':
          // These errors carry a detailed fix message — show it directly.
          return error.message ??
              'Google Sign-In is not configured. '
                  'Add the app SHA-1 in Firebase Console → Project Settings → '
                  'Your Apps → "com.arrowcoders.foodapp".';
        case 'requires-recent-login':
          return 'Please sign in again to continue';
        case 'invalid-verification-code':
          return 'Invalid OTP code';
        case 'session-expired':
          return 'OTP expired. Request a new code';
        case 'invalid-phone-number':
          return 'Enter a valid phone number with country code';
        default:
          return error.message ?? 'Authentication failed. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  /// Formats Indian numbers to E.164 when user types 10 digits.
  static String toE164Phone(String raw, {String defaultCountryCode = '+91'}) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (raw.trim().startsWith('+')) return '+$digits';
    if (digits.length == 10) return '$defaultCountryCode$digits';
    if (digits.startsWith('91') && digits.length == 12) return '+$digits';
    return '$defaultCountryCode$digits';
  }
}
