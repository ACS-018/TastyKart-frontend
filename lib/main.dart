import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'constants/color_constants.dart';
import 'models/admin_models.dart';
import 'screens/auth_gate.dart';
import 'services/firestore_service.dart';
import 'state/cart_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const TastyKartApp());
}

class TastyKartApp extends StatefulWidget {
  const TastyKartApp({super.key});

  @override
  State<TastyKartApp> createState() => _TastyKartAppState();
}

class _TastyKartAppState extends State<TastyKartApp> {
  final CartController _cart = CartController();

  @override
  void initState() {
    super.initState();
    FirestoreService.adminSettings().listen((doc) {
      _cart.applyCharges(PlatformCharges.fromSettingsDoc(doc));
    });
  }

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CartScope(
      controller: _cart,
      child: MaterialApp(
        title: 'Tasty Kart',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            surface: AppColors.background,
          ),
          scaffoldBackgroundColor: AppColors.background,
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        home: const AuthGate(),
      ),
    );
  }
}
