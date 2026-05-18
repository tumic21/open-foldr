import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/client/watch_client.dart';

void main() {
  group('FileEvent.fromJson', () {
    test('parses created event', () {
      final e = FileEvent.fromJson({'type': 'created', 'path': '/foo.txt'});
      expect(e.type, 'created');
      expect(e.path, '/foo.txt');
      expect(e.movedTo, isNull);
    });

    test('parses modified event', () {
      final e = FileEvent.fromJson({'type': 'modified', 'path': '/bar.txt'});
      expect(e.type, 'modified');
      expect(e.path, '/bar.txt');
      expect(e.movedTo, isNull);
    });

    test('parses deleted event', () {
      final e = FileEvent.fromJson({'type': 'deleted', 'path': '/baz.txt'});
      expect(e.type, 'deleted');
      expect(e.path, '/baz.txt');
      expect(e.movedTo, isNull);
    });

    test('parses moved event with movedTo', () {
      final e = FileEvent.fromJson({
        'type': 'moved',
        'path': '/old.txt',
        'movedTo': '/new.txt',
      });
      expect(e.type, 'moved');
      expect(e.path, '/old.txt');
      expect(e.movedTo, '/new.txt');
    });

    test('movedTo is null when absent from json', () {
      final e = FileEvent.fromJson({'type': 'moved', 'path': '/old.txt'});
      expect(e.movedTo, isNull);
    });
  });

  group('WatchClient', () {
    test('dispose is idempotent — no double-close errors', () async {
      final client = WatchClient(
        baseUrl: 'http://localhost:8080/v1',
        sessionToken: 'tok',
        alias: 'home',
        watchPath: '/',
      );
      // Dispose without connecting — should not throw.
      client.dispose();
      // Second dispose must also not throw.
      client.dispose();
    });

    test('dispose before connect does not emit events', () async {
      final client = WatchClient(
        baseUrl: 'http://localhost:8080/v1',
        sessionToken: 'tok',
        alias: 'home',
        watchPath: '/',
      );
      final received = <FileEvent>[];
      client.events.listen(received.add);
      client.dispose();
      // Small delay to confirm no events arrive.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    });

    test('buildWsUri converts http to ws scheme', () {
      final client = WatchClient(
        baseUrl: 'http://127.0.0.1:9000/v1',
        sessionToken: 'mytoken',
        alias: 'docs',
        watchPath: '/subdir',
      );
      final uri = client.buildWsUri();
      expect(uri.scheme, 'ws');
      expect(uri.host, '127.0.0.1');
      expect(uri.port, 9000);
      expect(uri.path, '/v1/roots/docs/watch');
      expect(uri.queryParameters['path'], '/subdir');
      expect(uri.queryParameters['token'], 'mytoken');
      client.dispose();
    });

    test('buildWsUri converts https to wss scheme', () {
      final client = WatchClient(
        baseUrl: 'https://example.com/v1',
        sessionToken: 'securetoken',
        alias: 'media',
        watchPath: '/photos',
      );
      final uri = client.buildWsUri();
      expect(uri.scheme, 'wss');
      client.dispose();
    });

    test('events stream is broadcast', () {
      final client = WatchClient(
        baseUrl: 'http://localhost:8080/v1',
        sessionToken: 'tok',
        alias: 'home',
        watchPath: '/',
      );
      // Should be able to subscribe multiple times (broadcast stream).
      final sub1 = client.events.listen((_) {});
      final sub2 = client.events.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
      client.dispose();
    });
  });
}
