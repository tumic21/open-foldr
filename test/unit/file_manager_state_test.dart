/// Unit tests for Phase 3 — [FileManagerState] (sort, navigation, multi-select,
/// clipboard) and Phase 4 — dialog helper functions.

import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/ui/screens/guest/file_manager_screen.dart';
import 'package:open_foldr/ui/widgets/file_manager/sort_menu.dart';
import 'package:open_foldr/ui/widgets/file_manager/view_mode_toggle.dart';
import 'package:open_foldr/ui/widgets/file_manager/dialogs/conflict_dialog.dart';

// ─── Fixture helpers ──────────────────────────────────────────────────────────

DateTime _dt(int second) =>
    DateTime(2024, 1, 1, 0, 0, second);

FileEntry _file(String name, {int size = 100, DateTime? modifiedAt}) =>
    FileEntry(
      name: name,
      path: '/$name',
      kind: 'file',
      size: size,
      modifiedAt: modifiedAt ?? _dt(0),
    );

FileEntry _dir(String name) => FileEntry(
      name: name,
      path: '/$name',
      kind: 'directory',
      size: 0,
      modifiedAt: _dt(0),
    );

// ─── FileManagerState ─────────────────────────────────────────────────────────

void main() {
  // ─── Navigation stack ───────────────────────────────────────────────────

  group('FileManagerState — navigation', () {
    test('starts at initial path', () {
      final s = FileManagerState(initialPath: '/');
      expect(s.currentPath, '/');
      expect(s.canGoUp, isFalse);
    });

    test('pushPath adds to stack', () {
      final s = FileManagerState();
      s.pushPath('/docs');
      expect(s.currentPath, '/docs');
      expect(s.canGoUp, isTrue);
    });

    test('popPath returns to previous path', () {
      final s = FileManagerState();
      s.pushPath('/docs');
      s.pushPath('/docs/sub');
      final popped = s.popPath();
      expect(popped, isTrue);
      expect(s.currentPath, '/docs');
    });

    test('popPath returns false at root', () {
      final s = FileManagerState();
      expect(s.popPath(), isFalse);
      expect(s.currentPath, '/');
    });

    test('navigateTo trims stack to known ancestor', () {
      final s = FileManagerState();
      s.pushPath('/a');
      s.pushPath('/a/b');
      s.pushPath('/a/b/c');
      s.navigateTo('/a');
      expect(s.currentPath, '/a');
      expect(s.canGoUp, isTrue);
    });

    test('navigateTo with unknown path resets stack', () {
      final s = FileManagerState();
      s.pushPath('/a');
      s.navigateTo('/z');
      expect(s.currentPath, '/z');
      expect(s.canGoUp, isFalse);
    });
  });

  // ─── setEntries / setError / setLoading ─────────────────────────────────

  group('FileManagerState — loading state', () {
    test('setEntries clears loading and error', () {
      final s = FileManagerState();
      s.setError('oops');
      s.setEntries([_file('a.txt')]);
      expect(s.isLoading, isFalse);
      expect(s.error, isNull);
      expect(s.entries.length, 1);
    });

    test('setError sets error and clears loading', () {
      final s = FileManagerState();
      s.setError('something went wrong');
      expect(s.isLoading, isFalse);
      expect(s.error, 'something went wrong');
    });

    test('setLoading clears error', () {
      final s = FileManagerState();
      s.setError('old error');
      s.setLoading();
      expect(s.isLoading, isTrue);
      expect(s.error, isNull);
    });
  });

  // ─── Sorting ────────────────────────────────────────────────────────────

  group('FileManagerState — sorting', () {
    test('dirs always come before files', () {
      final s = FileManagerState();
      s.setEntries([
        _file('z.txt'),
        _dir('alpha'),
        _file('a.txt'),
        _dir('zeta'),
      ]);
      expect(s.entries[0].isDirectory, isTrue);
      expect(s.entries[1].isDirectory, isTrue);
      expect(s.entries[2].isFile, isTrue);
      expect(s.entries[3].isFile, isTrue);
    });

    test('sort by name ascending (default)', () {
      final s = FileManagerState();
      s.setEntries([_file('c.txt'), _file('a.txt'), _file('b.txt')]);
      final names = s.entries.map((e) => e.name).toList();
      expect(names, ['a.txt', 'b.txt', 'c.txt']);
    });

    test('sort by name descending', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt'), _file('c.txt'), _file('b.txt')]);
      s.setSortBy(SortField.name, SortOrder.desc);
      final names = s.entries.map((e) => e.name).toList();
      expect(names, ['c.txt', 'b.txt', 'a.txt']);
    });

    test('sort by size ascending', () {
      final s = FileManagerState();
      s.setEntries([
        _file('big.txt', size: 1000),
        _file('tiny.txt', size: 10),
        _file('mid.txt', size: 500),
      ]);
      s.setSortBy(SortField.size, SortOrder.asc);
      final sizes = s.entries.map((e) => e.size).toList();
      expect(sizes, [10, 500, 1000]);
    });

    test('sort by date descending', () {
      final s = FileManagerState();
      s.setEntries([
        _file('old.txt', modifiedAt: _dt(1)),
        _file('new.txt', modifiedAt: _dt(3)),
        _file('mid.txt', modifiedAt: _dt(2)),
      ]);
      s.setSortBy(SortField.date, SortOrder.desc);
      final names = s.entries.map((e) => e.name).toList();
      expect(names, ['new.txt', 'mid.txt', 'old.txt']);
    });

    test('sort by type groups same extension together', () {
      final s = FileManagerState();
      s.setEntries([
        _file('a.png'),
        _file('b.txt'),
        _file('c.png'),
        _file('d.txt'),
      ]);
      s.setSortBy(SortField.type, SortOrder.asc);
      // .png before .txt alphabetically
      expect(s.entries[0].name, 'a.png');
      expect(s.entries[1].name, 'c.png');
      expect(s.entries[2].name, 'b.txt');
      expect(s.entries[3].name, 'd.txt');
    });

    test('setSortBy re-sorts existing entries', () {
      final s = FileManagerState();
      s.setEntries([_file('b.txt'), _file('a.txt')]);
      expect(s.entries[0].name, 'a.txt'); // default asc
      s.setSortBy(SortField.name, SortOrder.desc);
      expect(s.entries[0].name, 'b.txt');
    });
  });

  // ─── Multi-select ────────────────────────────────────────────────────────

  group('FileManagerState — multi-select', () {
    test('not in multi-select mode initially', () {
      final s = FileManagerState();
      expect(s.multiSelectMode, isFalse);
      expect(s.hasSelection, isFalse);
    });

    test('toggleSelect adds then removes a path', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      expect(s.selectedPaths.contains('/a.txt'), isTrue);
      expect(s.multiSelectMode, isTrue);
      s.toggleSelect('/a.txt');
      expect(s.selectedPaths.contains('/a.txt'), isFalse);
      expect(s.multiSelectMode, isFalse);
    });

    test('clearSelection empties selected set', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      s.toggleSelect('/b.txt');
      s.clearSelection();
      expect(s.selectedPaths, isEmpty);
    });

    test('selectAll selects all current entries', () {
      final s = FileManagerState();
      s.setEntries([_file('a.txt'), _file('b.txt'), _dir('sub')]);
      s.selectAll();
      expect(s.selectedPaths.length, 3);
    });
  });

  // ─── Clipboard ───────────────────────────────────────────────────────────

  group('FileManagerState — clipboard', () {
    test('copySelected sets clipboard with copy operation', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      s.copySelected('docs');
      expect(s.clipboard, isNotNull);
      expect(s.clipboard!.operation, 'copy');
      expect(s.clipboard!.items, contains('/a.txt'));
      expect(s.clipboard!.sourceAlias, 'docs');
    });

    test('cutSelected sets clipboard with cut operation', () {
      final s = FileManagerState();
      s.toggleSelect('/b.txt');
      s.cutSelected('docs');
      expect(s.clipboard!.operation, 'cut');
    });

    test('clearClipboard removes clipboard', () {
      final s = FileManagerState();
      s.toggleSelect('/a.txt');
      s.copySelected('docs');
      s.clearClipboard();
      expect(s.clipboard, isNull);
    });
  });

  // ─── ViewMode ────────────────────────────────────────────────────────────

  group('FileManagerState — viewMode', () {
    test('default is list', () {
      expect(FileManagerState().viewMode, ViewMode.list);
    });

    test('setViewMode changes mode', () {
      final s = FileManagerState();
      s.setViewMode(ViewMode.grid);
      expect(s.viewMode, ViewMode.grid);
    });
  });

  // ─── ChangeNotifier integration ──────────────────────────────────────────

  group('FileManagerState — ChangeNotifier', () {
    test('notifies listeners on pushPath', () {
      final s = FileManagerState();
      int calls = 0;
      s.addListener(() => calls++);
      s.pushPath('/docs');
      expect(calls, 1);
    });

    test('notifies listeners on setEntries', () {
      final s = FileManagerState();
      int calls = 0;
      s.addListener(() => calls++);
      s.setEntries([_file('a.txt')]);
      expect(calls, 1);
    });

    test('notifies listeners on toggleSelect', () {
      final s = FileManagerState();
      int calls = 0;
      s.addListener(() => calls++);
      s.toggleSelect('/x.txt');
      expect(calls, 1);
    });
  });

  // ─── Phase 4: Dialog helpers (pure logic, not widget tests) ─────────────

  group('ConflictResolution enum', () {
    test('has skip, replace, and keepBoth values', () {
      expect(ConflictResolution.values.length, 3);
      expect(ConflictResolution.values,
          containsAll([
            ConflictResolution.skip,
            ConflictResolution.replace,
            ConflictResolution.keepBoth,
          ]));
    });
  });

  group('ClipboardState', () {
    test('stores operation, items and sourceAlias', () {
      const c = ClipboardState(
        operation: 'copy',
        items: ['/a.txt'],
        sourceAlias: 'docs',
      );
      expect(c.operation, 'copy');
      expect(c.items, ['/a.txt']);
      expect(c.sourceAlias, 'docs');
    });
  });
}
