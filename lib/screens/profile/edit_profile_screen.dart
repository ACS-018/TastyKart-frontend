import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../constants/color_constants.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';
import '../../utils/app_feedback.dart';
import '../../widgets/app_screen_header.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final user = AuthService.currentUser;
    _name = TextEditingController(
      text: user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : (user?.email?.split('@').first ?? ''),
    );
    // Seed from Firebase Auth first; Firestore lookup will override below.
    _phone = TextEditingController(text: user?.phoneNumber ?? '');
    _email = TextEditingController(text: user?.email ?? '');

    // Fetch the Firestore-stored phone (saved via updateCustomerPhone during
    // checkout) and fill the field with the highest-priority value.
    _loadFirestorePhone(user);
  }

  /// Priority: Firestore `customers/{uid}.phone` → Firebase Auth → cart.
  Future<void> _loadFirestorePhone(User? user) async {
    final uid = user?.uid;
    if (uid == null) return;
    try {
      final snap = await FirestoreService.watchCustomerDoc(uid).first;
      if (!mounted) return;
      final data = snap.data() as Map<String, dynamic>?;
      final firestorePhone = (data?['phone'] as String? ?? '').trim();
      if (firestorePhone.isNotEmpty) {
        setState(() => _phone.text = firestorePhone);
        return;
      }
    } catch (_) {}
    // Fallback to cart if Auth phone is still empty after Firestore check.
    if (_phone.text.trim().isEmpty) {
      final cart = CartScope.maybeOf(context);
      final cartPhone = cart?.customerPhone.trim() ?? '';
      if (cartPhone.isNotEmpty &&
          cartPhone != '+91 00000 00000' &&
          !cartPhone.contains('00000')) {
        setState(() => _phone.text = cartPhone);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppFeedback.showError(context, 'Name is required');
      return;
    }

    final phone = _phone.text.trim();

    // Apply cart state synchronously for instant UI feedback.
    final cart = CartScope.maybeOf(context);
    cart?.setCustomer(name: name, phone: phone.isEmpty ? null : phone);

    // Pop and show success immediately — no spinner, no wait.
    if (mounted) {
      AppFeedback.showSuccess(context, 'Profile updated');
      Navigator.pop(context);
    }

    // Fire-and-forget the Firebase + Firestore updates in the background.
    final uid = AuthService.currentUser?.uid;
    try {
      await AuthService.currentUser?.updateDisplayName(name);
    } catch (_) {
      // Non-blocking — cart already updated.
    }
    // Persist name, email, and phone to Firestore so the profile header stream
    // (watchCustomerDoc) reflects changes immediately without waiting for
    // Firebase Auth to re-emit.
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('customers').doc(uid).set({
          'name': name,
          if (phone.isNotEmpty) 'phone': phone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Non-blocking.
      }
    }
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final photoUrl = user?.photoURL;
    final displayName = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : 'Customer';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Edit Profile',
            subtitle: 'Your Account Details',
            onBack: () => Navigator.pop(context),
            actions: [
              TextButton(
                onPressed: _save,
                child: const Text(
                  'Update',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: const Color(0xFFFFE8E8),
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? null
                          : Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _name,
                    decoration: _decoration('Full Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration('Phone Number'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _email,
                    readOnly: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration('Email'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
