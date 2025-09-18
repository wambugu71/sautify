/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautifyv2/main.dart';

void main() {
  testWidgets('App renders and shows bottom navigation tabs', (
    WidgetTester tester,
  ) async {
    // Build the app
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    // Verify bottom navigation exists with expected tabs
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
