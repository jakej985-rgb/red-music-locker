import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/views/dashboard_view.dart';
import 'package:app/views/library_view.dart';
import 'package:app/views/uploads_view.dart';
import 'package:app/views/playlists_view.dart';
import 'package:app/views/queue_view.dart';
import 'package:app/views/history_view.dart';
import 'package:app/views/family_view.dart';
import 'package:app/views/settings_view.dart';
import 'package:app/views/components/metadata_editor_dialog.dart';

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
      expect(tester.takeException(), isNull);
    });

    testWidgets('App shell renders on Tablet viewport (768x1024) without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(768 * 2.0, 1024 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const YTMSyncApp());
      await tester.pump();

      expect(find.text('RED MUSIC LOCKER'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('App shell renders on Desktop viewport (1440x900) without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const YTMSyncApp());
      await tester.pump();

      expect(find.text('RED MUSIC LOCKER'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 1. DashboardView
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

    // 2. LibraryView
    testWidgets('LibraryView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
      // Mobile
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: LibraryView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LibraryView), findsOneWidget);
      expect(find.text('MUSIC LIBRARY'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // 3. UploadsView
    testWidgets('UploadsView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: UploadsView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(UploadsView), findsOneWidget);
      expect(find.text('YOUTUBE MUSIC'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // 4. PlaylistsView
    testWidgets('PlaylistsView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: PlaylistsView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PlaylistsView), findsOneWidget);
      expect(find.text('YTM PLAYLISTS'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // 5. QueueView
    testWidgets('QueueView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
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
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // 6. HistoryView
    testWidgets('HistoryView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
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
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // 7. FamilyView
    testWidgets('FamilyView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: FamilyView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FamilyView), findsOneWidget);
      expect(find.text('Family Mode'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // 8. SettingsView
    testWidgets('SettingsView renders on narrow mobile bounds (360x640) and desktop (1440x900)', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: SettingsView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SettingsView), findsOneWidget);
      expect(find.text('Settings & Configuration'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Desktop
      tester.view.physicalSize = const Size(1440 * 1.0, 900 * 1.0);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // MetadataEditorDialog multi-viewport responsive testing (360, 390, 430, 768, 1024, 1440)
    for (final width in [360.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('MetadataEditorDialog renders cleanly at viewport width ${width.toInt()}px', (tester) async {
        final height = width < 600 ? 800.0 : 900.0;
        tester.view.physicalSize = Size(width * 1.0, height * 1.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: MetadataEditorDialog(
                trackVideoId: 'test_vid_123',
                initialTitle: 'Ride the Lightning',
                initialArtist: 'Metallica',
                initialAlbum: 'Ride the Lightning',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(MetadataEditorDialog), findsOneWidget);
        expect(find.text('Edit Track Metadata'), findsOneWidget);
        expect(find.text('BASIC INFORMATION'), findsOneWidget);
        expect(find.text('TRACK INFORMATION'), findsOneWidget);
        expect(find.text('ARTWORK'), findsOneWidget);
        expect(find.text('YOUTUBE MUSIC'), findsOneWidget);
        expect(find.text('Download & Upload with Match'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
