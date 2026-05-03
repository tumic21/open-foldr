import '../../models/shared_root.dart';
import '../path_guard.dart';

/// Holds all root aliases for the active session.
class RootRegistry {
  final Map<String, SharedRoot> _roots = {};
  final Map<String, PathGuard> _guards = {};

  /// Registers a [SharedRoot]. Alias must be unique.
  void register(SharedRoot root) {
    if (_roots.containsKey(root.alias)) {
      throw ArgumentError('Root alias "${root.alias}" is already registered');
    }
    _roots[root.alias] = root;
    _guards[root.alias] = PathGuard(root.localPath);
  }

  /// Removes a root by alias.
  void unregister(String alias) {
    _roots.remove(alias);
    _guards.remove(alias);
  }

  void clear() {
    _roots.clear();
    _guards.clear();
  }

  SharedRoot? get(String alias) => _roots[alias];
  PathGuard? guard(String alias) => _guards[alias];
  List<SharedRoot> get all => _roots.values.toList();
  bool get isEmpty => _roots.isEmpty;
}
