import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/presentation/login_screen.dart';

void main() {
  // The full app needs an initialized Supabase client, so test the login
  // screen on its own instead.
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
