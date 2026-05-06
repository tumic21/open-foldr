/// Unit tests for Phase 7 — search and sort in [FileManagerState],
/// and widget-level tests for search UI in [FileManagerScreen].

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/ui/screens/guest/file_manager_screen.dart';
import 'package:open_foldr/ui/widgets/file_manager/sort_menu.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

DateTime _dt([int day = 1]) => DateTime(2024, 1, day);

FileEntry _file(String name, {int size = 100, int day = 1}) => FileEntry(
      name: name,
      path: '/$name',
      kind: 'file',
      size: size,
      modifiedAt: _dt(day),
    );

FileEntry _dir(String name) => FileEntry(
      name: name,
      path: '/$name',
      kind: 'directory',
      size: 0,
      modifiedAt: _dt(),
    );

String _encodeEntries(List<FileEntry> entries) {
  final items = entries.map((e) => jsonEncode({
        'name': e.name,
        'path': e.path,
        'kind': e.kind,
        'size': e.size,
        'modifiedAt': e.modifiedAt.toIso8601String(),
      }));
  return '[${items.join(',')}]';
}

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
      return http.Response(
          '{"error":{"code":"NOT_FOUND","message":"x"}}', 404,
          headers: {'content-type': 'application/json'});
    }),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

// ─── Search — unit tests ──────────────────────────────────────────────────────

void main() {
  group('FileManagerState — search', () {
    test('filteredEntries returns all entries when query is empty', () {
      final s = FileManagerState();
      s.setEntries([_file('alpha.txt'), _file('beta.txt'), _dir('sub')]);
      expect(s.filteredEntries.length, 3);
    });

    test('filteredEntries filters by partial name (case-insensitive)', () {
      final s = FileManagerState();
      s.setEntries([_file('Alpha.txt'), _file('BETA.txt'), _file('gamma.dart')]);
      s.setSearchQuery('alpha');
      expect(s.filteredEntries.map((e) => e.name), ['Alpha.txt']);
    });

    test('filteredEntries is case-insensitive', () {
      final s = FileManagerState();
      s.setEntries([_file('Readme.md'), _file('notes.txt')]);
      s.setSearchQuery('README');
      expect(s.filteredEntries.length, 1);
      expect(s.filteredEntries.first.name, 'Readme.md');
    });

    test('filteredEntries matches substring in name', () {
      final s = FileManagerState();
      s.setEntries([
        _file('report_2024.pdf'),
        _file('summary.pdf'),
        _file('notes.txt'),
      ]);
      s.setSearchQuery('2024');
      expect(s.filteredEntries.length, 1);
      expect(s.filteredEntries.first.name, 'report_2024.pdf');
    });

    test('filteredEntries returns empty list when nothing matches', () {
      final s = FileManagerState();
      s.setEntries([_file('alpha.txt'), _file('beta.txt')]);
      s.setSearchQuery('zzz');
      expect(s.filteredEntries, isEmpty);
    });

    test('clearSearch resets filteredEntries to all entries', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt'), _file('b.txt')]);
      s.setSearchQuery('a');
      expect(s.filteredEntries.length, 1);
      s.clearSearch();
      expect(s.filteredEntries.length, 2);
    });

    test('searchQuery clears when pushPath is called', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt')]);
      s.setSearchQuery('a');
      s.pushPath('/sub');
      expect(s.searchQuery, isEmpty);
    });

    test('searchQuery clears when popPath is called', () {
      final s = FileManagerState();
      s.pushPath('/sub');
      s.setSearchQuery('x');
      s.popPath();
      expect(s.searchQuery, isEmpty);
    });

    test('searchQuery clears when navigateTo is called', () {
      final s = FileManagerState();
      s.setSearchQuery('x');
      s.navigateTo('/other');
      expect(s.searchQuery, isEmpty);
    });

    test('filteredEntries includes both dirs and files matching query', () {
      final s = FileManagerState();
      s.setEntries([_file('docs.txt'), _dir('docs'), _file('readme.md')]);
      s.setSearchQuery('docs');
      expect(s.filteredEntries.length, 2);
    });
  });

  // ─── Sort — unit tests ───────────────────────────────────────────────────────

  group('FileManagerState — sort', () {
    test('default sort is name ascending', () {
      final s = FileManagerState();
      s.setEntries([_file('z.txt'), _file('a.txt'), _file('m.txt')]);
      final names = s.entries.map((e) => e.name).toList();
      expect(names, ['a.txt', 'm.txt', 'z.txt']);
    });

    test('folders always appear before files', () {
      final s = FileManagerState();
      s.setEntries([_file('z.txt'), _dir('aaa'), _file('a.txt'), _dir('zzz')]);
      final kinds = s.entries.map((e) => e.kind).toList();
      expect(kinds.sublist(0, 2), everyElement('directory'));
      expect(kinds.sublist(2), everyElement('file'));
    });

    test('sort by name descending', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt'), _file('z.txt'), _file('m.txt')]);
      s.setSortBy(SortField.name, SortOrder.desc);
      final names = s.filteredEntries.map((e) => e.name).toList();
      expect(names, ['z.txt', 'm.txt', 'a.txt']);
    });

    test('sort by size ascending', () {
      final s = FileManagerState();
      s.setEntries([
        _file('big.txt', size: 1000),
        _file('tiny.txt', size: 10),
        _file('mid.txt', size: 500),
      ]);
      s.setSortBy(SortField.size, SortOrder.asc);
      final names = s.filteredEntries.map((e) => e.name).toList();
      expect(names, ['tiny.txt', 'mid.txt', 'big.txt']);
    });

    test('sort by date descending', () {
      final s = FileManagerState();
      s.setEntries([
        _file('old.txt', day: 1),
        _file('new.txt', day: 30),
        _file('mid.txt', day: 15),
      ]);
      s.setSortBy(SortField.date, SortOrder.desc);
      final names = s.filteredEntries.map((e) => e.name).toList();
      expect(names, ['new.txt', 'mid.txt', 'old.txt']);
    });

    test('sort by type groups same extension together', () {
      final s = FileManagerState();
      s.setEntries([
        _file('b.txt'),
        _file('a.dart'),
        _file('c.txt'),
        _file('z.dart'),
      ]);
      s.setSortBy(SortField.type, SortOrder.asc);
      final names = s.filteredEntries.map((e) => e.name).toList();
      // .dart < .txt alphabetically
      expect(names.sublist(0, 2), containsAll(['a.dart', 'z.dart']));
      expect(names.sublist(2), containsAll(['b.txt', 'c.txt']));
    });

    test('filtered entries respect current sort order', () {
      final s = FileManagerState();
      s.setEntries([_file('album.txt'), _file('alert.txt'), _file('python.txt')]);
      s.setSortBy(SortField.name, SortOrder.desc);
      s.setSearchQuery('al'); // matches album and alert, NOT python
      // descending: 'alert' > 'album' (e > b) → alert.txt first
      final names = s.filteredEntries.map((e) => e.name).toList();
      expect(names, ['alert.txt', 'album.txt']);
    });
  });

  // ─── Search UI — widget tests ─────────────────────────────────────────────

  group('FileManagerScreen — search UI', () {
    testWidgets('search icon is visible in AppBar', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('tapping search icon shows text field', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping close icon hides search bar', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('typing in search filters the list', (tester) async {
      final entries = [
        _file('alpha.txt'),
        _file('beta.txt'),
        _file('gamma.dart'),
      ];
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient(entries),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();

      expect(find.text('alpha.txt'), findsOneWidget);
      expect(find.text('beta.txt'), findsNothing);
      expect(find.text('gamma.dart'), findsNothing);
    });

    testWidgets('backspace edits the active search query', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('alpha.txt')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(find.text('alph'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
    });

    testWidgets('delete edits the active search query', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('alpha.txt')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();

      final editable = tester.state<EditableTextState>(find.byType(EditableText));
      editable.updateEditingValue(const TextEditingValue(
        text: 'alpha',
        selection: TextSelection.collapsed(offset: 0),
      ));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(find.text('lpha'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
    });

    testWidgets('empty search result shows "No results" message',
        (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('alpha.txt')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();

      expect(find.textContaining('No results'), findsOneWidget);
    });

    testWidgets('sort menu icon is visible alongside search', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });
  });

  group('FileManagerScreen — open file routing', () {
    // On desktop (Linux), files open on double-tap; single tap selects.
    testWidgets('routes text files as text', (tester) async {
      String? openedKind;
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('readme.txt')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
        onOpenFile: (kind, _) => openedKind = kind,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('readme.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('readme.txt'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(openedKind, 'text');
    });

    testWidgets('routes image files as image', (tester) async {
      String? openedKind;
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('photo.jpg')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
        onOpenFile: (kind, _) => openedKind = kind,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('photo.jpg'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('photo.jpg'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(openedKind, 'image');
    });

    testWidgets('routes pdf files as pdf', (tester) async {
      String? openedKind;
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('guide.pdf')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
        onOpenFile: (kind, _) => openedKind = kind,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('guide.pdf'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('guide.pdf'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(openedKind, 'pdf');
    });

    testWidgets('routes unknown files to download fallback', (tester) async {
      String? openedKind;
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('archive.bin')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
        onOpenFile: (kind, _) => openedKind = kind,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('archive.bin'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('archive.bin'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(openedKind, 'download');
    });

    testWidgets('unknown file double-click asks confirmation before download',
        (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([_file('archive.bin')]),
        alias: 'docs',
        role: 'viewer',
        watcherFactory: null,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('archive.bin'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('archive.bin'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Download file?'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });
  });
}
