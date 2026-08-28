import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasty_kart/main.dart';

void main() {
  testWidgets('Login screen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const TastyKartApp());

    // App should launch without crashing
    expect(find.byType(MaterialApp), findsOneWidget);

    // Sign In button should be visible
    expect(find.text('Sign In'), findsOneWidget);
  });
}
