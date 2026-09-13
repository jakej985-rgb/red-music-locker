import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/views/dashboard_view.dart';
import 'package:app/views/queue_view.dart';
import 'package:app/views/history_view.dart';

void main() {
  group('Responsive Layout Viewport Tests', () {
    testWidgets('App shell renders on Mobile viewport (390x844) without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const YTMSyncApp());
      await tester.pump();

      expect(find.text('RED MUSIC LOCKER'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('App shell renders on Tablet viewport (768x1024) without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(768 * 2.0, 1024 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const YTMSyncApp());
      await tester.pump();

      expect(find.text('RED MUSIC LOCKER'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('App shell renders on Desktop viewport (1440x900) without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const YTMSyncApp());
      await tester.pump();

      expect(find.text('RED MUSIC LOCKER'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('DashboardView renders on narrow mobile bounds (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DashboardView(onNavigateTab: (_) {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DashboardView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('QueueView renders on narrow mobile bounds (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: QueueView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(QueueView), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
    });

    testWidgets('HistoryView renders on narrow mobile bounds (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: HistoryView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(HistoryView), findsOneWidget);
      expect(find.text('Upload History & Activity'), findsOneWidget);
    });
  });
}
