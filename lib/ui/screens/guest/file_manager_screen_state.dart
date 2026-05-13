part of 'file_manager_screen.dart';

// ─── State model ────────────────────────────────────────────────────────────

class ClipboardState {
  final String operation; // 'copy' or 'cut'
  final List<String> items;
  final String sourceAlias;

  const ClipboardState({
    required this.operation,
    required this.items,
    required this.sourceAlias,
  });
}

class FileManagerState extends ChangeNotifier {
  final List<String> _pathStack;
  List<FileEntry> entries = [];
  SortField sortBy = SortField.name;
  SortOrder sortOrder = SortOrder.asc;
  ViewMode viewMode = ViewMode.list;
  final Set<String> selectedPaths = {};
  ClipboardState? clipboard;
  bool isLoading = true;
  String? error;

  FileManagerState({String initialPath = '/'}) : _pathStack = [initialPath];

  String get currentPath => _pathStack.last;
  bool get canGoUp => _pathStack.length > 1;

  void pushPath(String path) {
    _pathStack.add(path);
    _searchQuery = '';
    notifyListeners();
  }

  bool popPath() {
    if (_pathStack.length <= 1) return false;
    _pathStack.removeLast();
    _searchQuery = '';
    notifyListeners();
    return true;
  }

  void navigateTo(String path) {
    // Navigate to a specific ancestor path: trim the stack to that path.
    final idx = _pathStack.lastIndexOf(path);
    if (idx >= 0) {
      _pathStack.removeRange(idx + 1, _pathStack.length);
    } else {
      _pathStack
        ..clear()
        ..add(path);
    }
    _searchQuery = '';
    notifyListeners();
  }

  void setEntries(List<FileEntry> newEntries) {
    entries = _sortedEntries(newEntries);
    isLoading = false;
    error = null;
    notifyListeners();
  }

  void setError(String msg) {
    error = msg;
    isLoading = false;
    notifyListeners();
  }

  void setLoading() {
    isLoading = true;
    error = null;
    notifyListeners();
  }

  void setSortBy(SortField field, SortOrder order) {
    sortBy = field;
    sortOrder = order;
    entries = _sortedEntries(entries);
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    viewMode = mode;
    notifyListeners();
  }

  void toggleSelect(String path) {
    if (!selectedPaths.remove(path)) selectedPaths.add(path);
    notifyListeners();
  }

  void clearSelection() {
    selectedPaths.clear();
    notifyListeners();
  }

  void selectAll() {
    selectedPaths
      ..clear()
      ..addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  bool get hasSelection => selectedPaths.isNotEmpty;
  bool get multiSelectMode => selectedPaths.isNotEmpty;

  // ─── Search ───────────────────────────────────────────────────────────────

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase().trim();
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  List<FileEntry> get filteredEntries {
    if (_searchQuery.isEmpty) return entries;
    return entries
        .where((e) => e.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  void copySelected(String alias) {
    clipboard = ClipboardState(
      operation: 'copy',
      items: List.unmodifiable(selectedPaths),
      sourceAlias: alias,
    );
    notifyListeners();
  }

  void cutSelected(String alias) {
    clipboard = ClipboardState(
      operation: 'cut',
      items: List.unmodifiable(selectedPaths),
      sourceAlias: alias,
    );
    notifyListeners();
  }

  void clearClipboard() {
    clipboard = null;
    notifyListeners();
  }

  List<FileEntry> _sortedEntries(List<FileEntry> src) {
    final dirs = src.where((e) => e.isDirectory).toList();
    final files = src.where((e) => e.isFile).toList();

    int Function(FileEntry, FileEntry) cmp = switch (sortBy) {
      SortField.name => (a, b) => a.name.compareTo(b.name),
      SortField.size => (a, b) => a.size.compareTo(b.size),
      SortField.date => (a, b) => a.modifiedAt.compareTo(b.modifiedAt),
      SortField.type => (a, b) {
        final extA = a.name.contains('.')
            ? a.name.substring(a.name.lastIndexOf('.'))
            : '';
        final extB = b.name.contains('.')
            ? b.name.substring(b.name.lastIndexOf('.'))
            : '';
        final ext = extA.compareTo(extB);
        return ext != 0 ? ext : a.name.compareTo(b.name);
      },
    };

    if (sortOrder == SortOrder.desc) {
      final base = cmp;
      cmp = (a, b) => base(b, a);
    }

    dirs.sort(cmp);
    files.sort(cmp);
    return [...dirs, ...files];
  }
}
