// Basic Flutter widget test for Bondhu app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bondhu_flutter/main.dart';

void main() {
  testWidgets('App loads (BondhuApp smoke test)', (WidgetTester tester) async {
    await tester.pumpWidget(const BondhuApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
