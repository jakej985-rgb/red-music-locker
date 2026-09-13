import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/views/queue_view.dart';
import 'package:app/core/theme/app_theme.dart';

void main() {
  group('QueueView Widget Tests', () {
    testWidgets('QueueView initializes and renders initial state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: QueueView(),
          ),
        ),
      );

      // Initial frame renders page header and telemetry
      await tester.pump();

      expect(find.byType(QueueView), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('OPERATIONS & PIPELINE'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('ATTENTION'), findsOneWidget);
      expect(find.text('IN PIPELINE'), findsOneWidget);
      expect(find.text('UPLOADS'), findsOneWidget);
    });
  });
}
