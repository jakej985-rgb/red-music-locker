import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/views/dashboard_view.dart';
import 'package:app/core/theme/app_theme.dart';

void main() {
  group('DashboardView Widget Tests', () {
    testWidgets('DashboardView initializes and renders initial state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DashboardView(onNavigateTab: (index) {}),
          ),
        ),
      );

      // Initial frame will render either loading state or error state if backend unreachable
      await tester.pump();

      expect(
        find.byType(DashboardView),
        findsOneWidget,
      );
    });
  });
}
