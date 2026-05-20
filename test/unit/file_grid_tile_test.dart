import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/ui/widgets/file_manager/file_grid_tile.dart';

void main() {
  FileClient makeClient() {
    return FileClient(
      baseUrl: 'http://localhost:7432/v1',
      sessionToken: 'tok',
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 132, height: 160, child: child),
        ),
      ),
    );
  }

  testWidgets('grid tile does not overflow with long file names', (
    tester,
  ) async {
    final entry = FileEntry(
      name: 'very-long-document-name-that-would-normally-overflow-in-grid.txt',
      path: '/very-long-document-name-that-would-normally-overflow-in-grid.txt',
      kind: 'file',
      size: 123,
      modifiedAt: DateTime(2026, 5, 20),
    );

    await tester.pumpWidget(
      wrap(
        FileGridTile(
          client: makeClient(),
          alias: 'downloads',
          entry: entry,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FileGridTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
