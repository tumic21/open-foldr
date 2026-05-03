/// Roles that can be assigned to a paired device session.
enum Role {
  viewer,
  editor,
  owner;

  bool canRead() => true;
  bool canWrite() => this == editor || this == owner;
  bool canDelete() => this == owner;
  bool canAdmin() => this == owner;

  String get displayName => switch (this) {
        viewer => 'Viewer',
        editor => 'Editor',
        owner => 'Owner',
      };
}
