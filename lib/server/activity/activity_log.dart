import 'dart:async';

/// A single activity event logged by the server.
class ActivityEvent {
  final String id;
  final DateTime timestamp;
  final String deviceId;
  final String deviceName;
  final String rootAlias;
  final String operation;
  final String path;
  final String result;

  const ActivityEvent({
    required this.id,
    required this.timestamp,
    required this.deviceId,
    required this.deviceName,
    required this.rootAlias,
    required this.operation,
    required this.path,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'deviceName': deviceName,
        'rootAlias': rootAlias,
        'operation': operation,
        'path': path,
        'result': result,
      };
}

/// Records activity events and exposes a stream for live monitoring.
class ActivityLog {
  final int retentionDays;
  final _controller = StreamController<ActivityEvent>.broadcast();
  final List<ActivityEvent> _events = [];

  ActivityLog({this.retentionDays = 14});

  Stream<ActivityEvent> get stream => _controller.stream;
  List<ActivityEvent> get events => List.unmodifiable(_events);

  void record({
    required String id,
    required String deviceId,
    required String deviceName,
    required String rootAlias,
    required String operation,
    required String path,
    required String result,
  }) {
    _prune();
    final event = ActivityEvent(
      id: id,
      timestamp: DateTime.now().toUtc(),
      deviceId: deviceId,
      deviceName: deviceName,
      rootAlias: rootAlias,
      operation: operation,
      path: path,
      result: result,
    );
    _events.add(event);
    _controller.add(event);
  }

  void clear() => _events.clear();

  void _prune() {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    _events.removeWhere((e) => e.timestamp.isBefore(cutoff));
  }

  void dispose() => _controller.close();
}
