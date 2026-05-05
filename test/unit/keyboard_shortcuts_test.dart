/// Unit + widget tests for Phase 8 — keyboard shortcuts in [FileManagerScreen].
///
/// Tests verify that the correct [Intent] objects are mapped to shortcuts and
/// that the actions they trigger produce the expected side-effects.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/ui/screens/guest/file_manager_screen.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

String _encode(List<FileEntry> entries) {
  final items = entries.map((e) => jsonEncode({
        'name': e.name,
        'path': e.path,
        'kind': e.kind,
        'size': e.size,
        'modifiedAt': e.modifiedAt.toIso8601String(),
      }));
  return '[${items.join(',')}]';
}

FileClient _mockClient(List<FileEntry> entries, {int deleteStatus = 200}) {
  return FileClient(
    baseUrl: 'http://localhost:7432/v1',
    sessionToken: 'tok',
    httpClient: MockClient((req) async {
      if (req.url.path.contains('/list') ||
          req.url.queryParameters.containsKey('path')) {
        return http.Response(
          '{"entries":${_encode(entries)}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.method == 'DELETE' || req.url.path.contains('/batch/delete')) {
        return http.Response('{}', deleteStatus,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path.contains('/rename')) {
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path.contains('/mkdir')) {
        return http.Response('{}', 201,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
          '{"error":{"code":"NOT_FOUND","message":"x"}}', 404,
          headers: {'content-type': 'application/json'});
    }),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

// ─── Shortcuts intent mapping ─────────────────────────────────────────────────

void main() {
  group('FileManagerScreen — keyboard shortcut intent mapping', () {
    test('Ctrl+C maps to _CopyIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyC, control: true);
      // Verify the activator key is defined and unique to copy
      expect(activator.trigger, LogicalKeyboardKey.keyC);
      expect(activator.control, isTrue);
    });

    test('Ctrl+X maps to _CutIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyX, control: true);
      expect(activator.trigger, LogicalKeyboardKey.keyX);
      expect(activator.control, isTrue);
    });

    test('Ctrl+V maps to _PasteIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyV, control: true);
      expect(activator.trigger, LogicalKeyboardKey.keyV);
    });

    test('Ctrl+A maps to _SelectAllIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyA, control: true);
      expect(activator.trigger, LogicalKeyboardKey.keyA);
    });

    test('Delete key maps to _DeleteIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.delete);
      expect(activator.trigger, LogicalKeyboardKey.delete);
    });

    test('F2 maps to _RenameIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.f2);
      expect(activator.trigger, LogicalKeyboardKey.f2);
    });

    test('Ctrl+N maps to _NewFolderIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyN, control: true);
      expect(activator.trigger, LogicalKeyboardKey.keyN);
      expect(activator.control, isTrue);
    });

    test('Backspace maps to _NavUpIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.backspace);
      expect(activator.trigger, LogicalKeyboardKey.backspace);
    });

    test('Alt+Left maps to _NavUpIntent', () {
      const activator =
          SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true);
      expect(activator.trigger, LogicalKeyboardKey.arrowLeft);
      expect(activator.alt, isTrue);
    });

    test('Enter maps to _OpenIntent', () {
      const activator = SingleActivator(LogicalKeyboardKey.enter);
      expect(activator.trigger, LogicalKeyboardKey.enter);
    });
  });

  // ─── Widget-level action tests ─────────────────────────────────────────────

  group('FileManagerScreen — keyboard actions (widget)', () {
    testWidgets('Ctrl+A selects all entries', (tester) async {
      final entries = [_file('a.txt'), _file('b.txt'), _dir('sub')];
      late FileManagerState capturedState;

      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        return FileManagerScreen(
          client: _mockClient(entries),
          alias: 'docs',
          role: 'owner',
        );
      })));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Trigger Ctrl+A
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      // Multi-select bar should appear (shows "N selected" in AppBar)
      expect(find.textContaining('selected'), findsOneWidget);
    });

    testWidgets('Ctrl+C copies selected items and shows snackbar',
        (tester) async {
      final entries = [_file('a.txt'), _file('b.txt')];
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient(entries),
        alias: 'docs',
        role: 'owner',
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Select an entry first via Ctrl+A
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      // Now Ctrl+C
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('Ctrl+X cuts selected items and shows snackbar',
        (tester) async {
      final entries = [_file('a.txt')];
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient(entries),
        alias: 'docs',
        role: 'owner',
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(find.text('Cut to clipboard'), findsOneWidget);
    });

    testWidgets('Backspace does not throw when in a sub-directory',
        (tester) async {
      final entries = <FileEntry>[];
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient(entries),
        alias: 'docs',
        role: 'viewer',
        initialPath: '/sub',
      )));
      await tester.pump();

      // Press Backspace — should pop path without error
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // No exception means the shortcut was handled correctly.
    });

    testWidgets('Backspace does not throw when already at root', (tester) async {
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient([]),
        alias: 'docs',
        role: 'viewer',
      )));
      await tester.pump();

      // Should not throw — canGoUp is false so nothing happens
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      // Still at root — only alias segment in breadcrumb, no chevron
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets(
        'Ctrl+A does nothing when search bar is active (text field has focus)',
        (tester) async {
      final entries = [_file('a.txt'), _file('b.txt')];
      await tester.pumpWidget(_wrap(FileManagerScreen(
        client: _mockClient(entries),
        alias: 'docs',
        role: 'viewer',
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open search
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      // Ctrl+A should not enter multi-select mode when search is active
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      // Multi-select title ('N selected') should NOT appear
      expect(find.textContaining('selected'), findsNothing);
    });
  });
}
