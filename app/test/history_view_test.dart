import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/views/history_view.dart';
import 'package:app/core/theme/app_theme.dart';

void main() {
  group('HistoryView Widget Tests', () {
    testWidgets('HistoryView initializes and renders initial state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: HistoryView(),
          ),
        ),
      );

      // Initial frame renders page header and telemetry
      await tester.pump();

      expect(find.byType(HistoryView), findsOneWidget);
      expect(find.text('Upload History & Activity'), findsOneWidget);
      expect(find.text('AUDIT TRAIL & LOGS'), findsOneWidget);
      expect(find.text('TOTAL JOBS'), findsOneWidget);
      expect(find.text('SUCCEEDED'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('SUCCESS RATE'), findsOneWidget);
    });
  });
}
