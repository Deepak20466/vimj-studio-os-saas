import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vimj_attendance/main.dart';

void main() {
  testWidgets('App boots to the splash/login flow', (WidgetTester tester) async {
    await tester.pumpWidget(const VimjApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
