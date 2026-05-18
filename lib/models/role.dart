/// Roles that can be assigned to a paired device session.
enum Role {
  viewer,
  editor,
  owner;

  int get rank => index;

  bool canRead() => true;
  bool canWrite() => this == editor || this == owner;
  bool canDelete() => this == owner;
  bool canAdmin() => this == owner;

  bool atLeast(Role other) => rank >= other.rank;

  static Role highest(Iterable<Role> roles) {
    var resolved = Role.viewer;
    for (final role in roles) {
      if (role.rank > resolved.rank) resolved = role;
    }
    return resolved;
  }

  String get displayName => switch (this) {
        viewer => 'Viewer',
        editor => 'Editor',
        owner => 'Owner',
      };
}
