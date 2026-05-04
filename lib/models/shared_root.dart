import 'role.dart';

/// Represents a folder shared by the host under a named alias.
class SharedRoot {
  final String alias;
  final String localPath;
  final Role minimumRole;

  const SharedRoot({
    required this.alias,
    required this.localPath,
    this.minimumRole = Role.viewer,
  });

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'path': localPath,
        'minimumRole': minimumRole.name,
      };

  factory SharedRoot.fromJson(Map<String, dynamic> json) => SharedRoot(
        alias: json['alias'] as String,
        localPath: json['path'] as String,
        minimumRole: Role.values.firstWhere(
          (r) => r.name == json['minimumRole'],
          orElse: () => Role.viewer,
        ),
      );
}
