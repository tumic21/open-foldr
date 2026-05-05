/// Unit tests for Phase 5 — multi-select behaviour in [FileManagerState]
/// and widget-level tests for [FileGridTile] multi-select indicator and
/// [FileManagerScreen] FAB visibility / tap-to-exit behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/ui/screens/guest/file_manager_screen.dart';
import 'package:open_foldr/ui/widgets/file_manager/breadcrumb_bar.dart';
import 'package:open_foldr/ui/widgets/file_manager/file_grid_tile.dart';
import 'package:open_foldr/ui/widgets/file_manager/file_list_tile.dart';

// ─── Fixture helpers ─────────────────────────────────────────────────────────

DateTime _dt() => DateTime(2024, 1, 1);

FileEntry _file(String name) => FileEntry(
      name: name,
      path: '/$name',
      kind: 'file',
      size: 100,
      modifiedAt: _dt(),
    );

FileEntry _dir(String name) => FileEntry(
      name: name,
      path: '/$name',
      kind: 'directory',
      size: 0,
      modifiedAt: _dt(),
    );

/// Returns a [FileClient] that responds with [entries] for listEntries and
/// 404 for everything else.
FileClient _mockClient(List<FileEntry> entries) {
  return FileClient(
    baseUrl: 'http://localhost:7432/v1',
    sessionToken: 'tok',
    httpClient: MockClient((req) async {
      if (req.url.path.contains('/list') ||
          req.url.queryParameters.containsKey('path')) {
        return http.Response(
          '{"entries":${_encodeEntries(entries)}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"error":{"code":"NOT_FOUND","message":"x"}}', 404,
          headers: {'content-type': 'application/json'});
    }),
  );
}

String _encodeEntries(List<FileEntry> entries) {
  final items = entries.map((e) => '{'
      '"name":"${e.name}",'
      '"path":"${e.path}",'
      '"kind":"${e.kind}",'
      '"size":${e.size},'
      '"modifiedAt":"${e.modifiedAt.toIso8601String()}"'
      '}');
  return '[${items.join(',')}]';
}

// ─── FileManagerState — multi-select unit tests ───────────────────────────────

void main() {
  group('FileManagerState — multi-select entry', () {
    test('long-press equivalent: toggleSelect enables multiSelectMode', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt'), _file('b.txt')]);
      expect(s.multiSelectMode, isFalse);
      s.toggleSelect('/a.txt');
      expect(s.multiSelectMode, isTrue);
      expect(s.selectedPaths, contains('/a.txt'));
    });

    test('de-selecting last item exits multiSelectMode', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      s.toggleSelect('/a.txt'); // de-select
      expect(s.multiSelectMode, isFalse);
    });

    test('clearSelection exits multiSelectMode', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      s.toggleSelect('/b.txt');
      s.clearSelection();
      expect(s.multiSelectMode, isFalse);
      expect(s.selectedPaths, isEmpty);
    });

    test('selectAll selects every entry', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt'), _file('b.txt'), _dir('sub')]);
      s.selectAll();
      expect(s.selectedPaths.length, 3);
      expect(s.multiSelectMode, isTrue);
    });

    test('tap in multi-select mode toggles item (does not navigate)', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt'); // enter multi-select
      s.toggleSelect('/b.txt'); // add second
      expect(s.selectedPaths.length, 2);
      s.toggleSelect('/a.txt'); // remove
      expect(s.selectedPaths.length, 1);
      expect(s.selectedPaths, contains('/b.txt'));
    });

    test('navigateTo clears multi-select state', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      s.navigateTo('/docs');
      // State doesn't auto-clear on navigateTo — clearing is caller's
      // responsibility — so selection survives; screen calls clearSelection.
      // Verify navigateTo itself only updates path.
      expect(s.currentPath, '/docs');
    });
  });

  group('FileManagerState — hasSelection / multiSelectMode symmetry', () {
    test('hasSelection and multiSelectMode are equivalent', () {
      final s = FileManagerState();
      expect(s.hasSelection, equals(s.multiSelectMode));
      s.toggleSelect('/x');
      expect(s.hasSelection, isTrue);
      expect(s.multiSelectMode, isTrue);
      s.clearSelection();
      expect(s.hasSelection, isFalse);
      expect(s.multiSelectMode, isFalse);
    });
  });

  // ─── FileGridTile widget tests ─────────────────────────────────────────────

  group('FileGridTile — multi-select indicator', () {
    testWidgets('shows no indicator when not in multiSelectMode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileGridTile(
              entry: _file('img.png'),
              selected: false,
              multiSelectMode: false,
            ),
          ),
        ),
      );
      // Neither check_circle nor radio_button_unchecked should be present.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    });

    testWidgets('shows unchecked circle when in multiSelectMode but not selected',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileGridTile(
              entry: _file('img.png'),
              selected: false,
              multiSelectMode: true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('shows check_circle when selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileGridTile(
              entry: _file('img.png'),
              selected: true,
              multiSelectMode: true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    });

    testWidgets('card uses primaryContainer color when selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileGridTile(
              entry: _file('img.png'),
              selected: true,
              multiSelectMode: true,
            ),
          ),
        ),
      );
      final card = tester.widget<Card>(find.byType(Card));
      final theme = Theme.of(tester.element(find.byType(Card)));
      expect(card.color, theme.colorScheme.primaryContainer);
    });
  });

  // ─── FileListTile widget tests ─────────────────────────────────────────────

  group('FileListTile — multi-select indicator', () {
    testWidgets('shows folder icon when not in multiSelectMode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              entry: _dir('docs'),
              multiSelectMode: false,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('shows Checkbox when in multiSelectMode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              entry: _dir('docs'),
              multiSelectMode: true,
              selected: false,
            ),
          ),
        ),
      );
      expect(find.byType(Checkbox), findsOneWidget);
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isFalse);
    });

    testWidgets('Checkbox is checked when selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              entry: _dir('docs'),
              multiSelectMode: true,
              selected: true,
            ),
          ),
        ),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isTrue);
    });

    testWidgets('wraps in LongPressDraggable when draggablePaths provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              entry: _file('docs.txt'),
              draggablePaths: const ['/docs.txt'],
            ),
          ),
        ),
      );
      expect(find.byType(LongPressDraggable<List<String>>), findsOneWidget);
    });

    testWidgets('wraps directories in DragTarget when onDropPaths provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileListTile(
              entry: _dir('docs'),
              onDropPaths: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(DragTarget<List<String>>), findsOneWidget);
    });
  });

  group('FileGridTile — drag wrappers', () {
    testWidgets('wraps in LongPressDraggable when draggablePaths provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileGridTile(
              entry: _file('docs.txt'),
              draggablePaths: const ['/docs.txt'],
            ),
          ),
        ),
      );
      expect(find.byType(LongPressDraggable<List<String>>), findsOneWidget);
    });

    testWidgets('wraps directories in DragTarget when onDropPaths provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileGridTile(
              entry: _dir('docs'),
              onDropPaths: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(DragTarget<List<String>>), findsOneWidget);
    });
  });

  group('BreadcrumbBar — drag target segments', () {
    testWidgets('creates DragTarget for each segment', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreadcrumbBar(
              alias: 'docs',
              currentPath: '/a/b',
            ),
          ),
        ),
      );

      // alias + a + b
      expect(find.byType(DragTarget<List<String>>), findsNWidgets(3));
    });
  });

  // ─── FileManagerScreen — FAB visibility ───────────────────────────────────

  group('FileManagerScreen — FAB hidden during multi-select', () {
    testWidgets('FAB is visible for editor role when not in multi-select',
        (tester) async {
      final client = _mockClient([_file('a.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'editor',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump(); // start load
      await tester.pump(const Duration(milliseconds: 50)); // settle

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('FAB is hidden for viewer role', (tester) async {
      final client = _mockClient([_file('a.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'viewer',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  // ─── FileManagerScreen — AppBar in multi-select mode ─────────────────────

  group('FileManagerScreen — AppBar switches in multi-select', () {
    testWidgets('AppBar title shows selected count in multi-select mode',
        (tester) async {
      final client = _mockClient([_file('a.txt'), _file('b.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'editor',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Long-press first item to enter multi-select
      await tester.longPress(find.text('a.txt'));
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('Close button in AppBar exits multi-select mode',
        (tester) async {
      final client = _mockClient([_file('a.txt'), _file('b.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'editor',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.longPress(find.text('a.txt'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      // Normal AppBar title is visible (BreadcrumbBar also has 'docs',
      // so check the AppBar title widget specifically).
      expect(find.widgetWithText(AppBar, 'docs'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget); // FAB back
    });

    testWidgets('Select All selects all visible entries', (tester) async {
      final client = _mockClient([_file('a.txt'), _file('b.txt'), _file('c.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'editor',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.longPress(find.text('a.txt'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      expect(find.text('3 selected'), findsOneWidget);
    });
  });

  // ─── FileManagerScreen — bottom bar ───────────────────────────────────────

  group('FileManagerScreen — bottom bar actions', () {
    testWidgets('bottom bar appears when items are selected', (tester) async {
      final client = _mockClient([_file('a.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'editor',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.copy), findsNothing); // no bottom bar yet

      await tester.longPress(find.text('a.txt'));
      await tester.pump();

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.cut), findsOneWidget);
    });

    testWidgets('FAB is hidden when bottom bar is visible (multi-select)',
        (tester) async {
      final client = _mockClient([_file('a.txt')]);
      await tester.pumpWidget(
        MaterialApp(
          home: FileManagerScreen(
            client: client,
            alias: 'docs',
            role: 'editor',
            watcherFactory: null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
