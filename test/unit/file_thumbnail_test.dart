import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/core/result.dart';
import 'package:open_foldr/ui/services/thumbnail_service.dart';
import 'package:open_foldr/ui/widgets/file_manager/file_thumbnail.dart';

class _FakeFileClient extends FileClient {
  _FakeFileClient(this.onGetThumbnail)
    : super(baseUrl: 'http://localhost:7432/v1', sessionToken: 'tok');

  final Future<Result<ThumbnailResponse>> Function(
    String alias,
    String path, {
    required int width,
    required int height,
    String fit,
    String? ifNoneMatch,
  }) onGetThumbnail;

  @override
  Future<Result<ThumbnailResponse>> getThumbnail(
    String alias,
    String path, {
    required int width,
    required int height,
    String fit = 'cover',
    String? ifNoneMatch,
  }) {
    return onGetThumbnail(
      alias,
      path,
      width: width,
      height: height,
      fit: fit,
      ifNoneMatch: ifNoneMatch,
    );
  }
}

FileEntry _imageEntry(String name) => FileEntry(
  name: name,
  path: '/$name',
  kind: 'file',
  size: 128,
  modifiedAt: DateTime(2026, 1, 1),
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() async {
    VisibilityDetectorController.instance.notifyNow();
  });

  testWidgets('does not fetch thumbnail until widget becomes visible', (
    tester,
  ) async {
    var calls = 0;
    final client = _FakeFileClient((
      alias,
      path, {
      required width,
      required height,
      String fit = 'cover',
      String? ifNoneMatch,
    }) async {
      calls++;
      return Ok(
        ThumbnailResponse(
          bytes: Uint8List.fromList([137, 80, 78, 71]),
          etag: 'etag-1',
          contentType: 'image/png',
        ),
      );
    });
    final service = ThumbnailService(enableDebugLogs: false);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 120,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 200),
                FileThumbnail(
                  client: client,
                  alias: 'docs',
                  entry: _imageEntry('photo.png'),
                  size: 48,
                  requestSize: 48,
                  service: service,
                ),
                const SizedBox(height: 200),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump();
    expect(calls, 0);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -220));
    await tester.pump();
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump();
    expect(calls, 1);
  });
}