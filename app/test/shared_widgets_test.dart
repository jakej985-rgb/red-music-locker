import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/shared/widgets/shared_widgets.dart';

void main() {
  group('Shared Widgets Unit & Render Tests', () {
    testWidgets('AppStatusBadge renders all semantic status types', (tester) async {
      for (final type in SyncStatusType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppStatusBadge(type: type),
            ),
          ),
        );
        expect(find.byType(AppStatusBadge), findsOneWidget);
      }
    });

    testWidgets('AppStatCard renders title, value, and triggers onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppStatCard(
              title: 'Total Tracks',
              value: '1,284',
              subtitle: '93% Synced',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('TOTAL TRACKS'), findsOneWidget);
      expect(find.text('1,284'), findsOneWidget);
      expect(find.text('93% Synced'), findsOneWidget);

      await tester.tap(find.byType(AppStatCard));
      expect(tapped, isTrue);
    });

    testWidgets('AppPageHeader renders title, kicker, and actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPageHeader(
              title: 'Music Library',
              kicker: 'Personal Locker',
              subtitle: '1,284 tracks',
              actions: [
                ElevatedButton(onPressed: () {}, child: const Text('Add Folder')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('PERSONAL LOCKER'), findsOneWidget);
      expect(find.text('Music Library'), findsOneWidget);
      expect(find.text('1,284 tracks'), findsOneWidget);
      expect(find.text('Add Folder'), findsOneWidget);
    });

    testWidgets('AppSearchBar triggers search callback', (tester) async {
      String query = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSearchBar(
              onChanged: (val) => query = val,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Metallica');
      expect(query, 'Metallica');
    });

    testWidgets('AppEmptyState renders title and calls action button', (tester) async {
      bool actionClicked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.folder_open_rounded,
              title: 'No music files found',
              description: 'Add a music directory to begin scanning.',
              actionLabel: 'Select Folder',
              onAction: () => actionClicked = true,
            ),
          ),
        ),
      );

      expect(find.text('No music files found'), findsOneWidget);
      expect(find.text('Add a music directory to begin scanning.'), findsOneWidget);
      await tester.tap(find.text('Select Folder'));
      expect(actionClicked, isTrue);
    });
  });
}
