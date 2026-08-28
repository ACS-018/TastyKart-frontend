import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firestore_paths.dart';

/// Customer Auth — Firebase Auth + Firestore profile sync.
/// Does not modify Admin security rules. Customer `role` is always `customer`.
class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

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
    await ensureCustomerProfile(cred.user);
    return cred;
  }

  static Future<UserCredential> signup({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await user.updateDisplayName(name.trim());
      await user.reload();
      await _writeCustomerDocs(
        user: _auth.currentUser ?? user,
        name: name.trim(),
        email: email.trim(),
        phone: phone,
      );
    }
    return cred;
  }

  /// Firebase emails a password-reset link (standard Auth flow).
  static Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
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
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'aborted-by-user',
        message: 'Google sign-in was cancelled.',
      );
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    await ensureCustomerProfile(
      cred.user,
      fallbackName: googleUser.displayName,
    );
    return cred;
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

  static Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
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

    // Mirror into Admin `customers` for ops dashboard (same project).
    await _db.collection(FirestorePaths.customers).doc(user.uid).set({
      'id': user.uid,
      'name': name,
      'email': email,
      'phone': phone ?? '',
      'status': 'active',
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
  }

  // ── Errors ───────────────────────────────────────────────────────────────

  static String messageFromError(Object error) {
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
