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

    testWidgets('AppAccountCard renders username, role, and handles tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAccountCard(
              username: 'alice',
              accountName: 'Alice Primary',
              accountEmail: 'alice@example.com',
              isConnected: true,
              isSelf: true,
              role: 'Owner',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('alice'), findsOneWidget);
      expect(find.text('Alice Primary'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);

      await tester.tap(find.byType(AppAccountCard));
      expect(tapped, isTrue);
    });

    testWidgets('AppProgressCard renders title, progress, and status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressCard(
              title: 'Syncing Library',
              subtitle: 'Uploading 14 of 50 tracks',
              progress: 0.28,
              statusText: '28% complete',
            ),
          ),
        ),
      );

      expect(find.text('Syncing Library'), findsOneWidget);
      expect(find.text('Uploading 14 of 50 tracks'), findsOneWidget);
      expect(find.text('28% complete'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('AppConfirmDialog renders title, message and returns user choice', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await AppConfirmDialog.show(
                    ctx,
                    title: 'Delete Playlist?',
                    message: 'This will remove the replica configuration.',
                    confirmLabel: 'Delete',
                    isDestructive: true,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Playlist?'), findsOneWidget);
      expect(find.text('This will remove the replica configuration.'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('AppActivityItem renders title, timestamp, and badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppActivityItem(
              title: 'Master of Puppets',
              subtitle: 'Metallica • Master of Puppets',
              timestamp: '2 mins ago',
              status: SyncStatusType.uploaded,
            ),
          ),
        ),
      );

      expect(find.text('Master of Puppets'), findsOneWidget);
      expect(find.text('Metallica • Master of Puppets'), findsOneWidget);
      expect(find.text('2 mins ago'), findsOneWidget);
      expect(find.byType(AppStatusBadge), findsOneWidget);
    });

    testWidgets('AppSectionHeader renders title and action widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSectionHeader(
              title: 'Active Replicas',
              subtitle: 'Locker-only copies',
              action: TextButton(onPressed: () {}, child: const Text('View All')),
            ),
          ),
        ),
      );

      expect(find.text('Active Replicas'), findsOneWidget);
      expect(find.text('Locker-only copies'), findsOneWidget);
      expect(find.text('View All'), findsOneWidget);
    });

    testWidgets('AppFilterBar renders options and calls onSelected', (tester) async {
      String selected = 'all';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFilterBar<String>(
              selectedValue: selected,
              options: const [
                FilterOption(value: 'all', label: 'All'),
                FilterOption(value: 'active', label: 'Active'),
                FilterOption(value: 'paused', label: 'Paused'),
              ],
              onSelected: (val) => selected = val,
            ),
          ),
        ),
      );

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.text('Active'));
      expect(selected, 'active');
    });

    testWidgets('AppSelectionToolbar renders count and action buttons', (tester) async {
      bool editTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSelectionToolbar(
              selectedCount: 5,
              onClearSelection: () {},
              actions: [
                ElevatedButton(
                  onPressed: () => editTapped = true,
                  child: const Text('Batch Edit'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('5 selected'), findsOneWidget);
      expect(find.text('Batch Edit'), findsOneWidget);
      await tester.tap(find.text('Batch Edit'));
      expect(editTapped, isTrue);
    });

    testWidgets('AppLoadingState renders message and indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLoadingState(
              message: 'Loading your music library...',
            ),
          ),
        ),
      );

      expect(find.text('Loading your music library...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AppErrorState renders error title, description, and retry action', (tester) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorState(
              title: 'Connection Failed',
              message: 'Failed to connect to backend server',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Connection Failed'), findsOneWidget);
      expect(find.text('Failed to connect to backend server'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      expect(retried, isTrue);
    });
  });
}
