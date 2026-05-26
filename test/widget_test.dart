import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/app.dart';
import 'package:open_foldr/ui/services/shared_folder_picker.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenFoldrApp());
    expect(find.byType(OpenFoldrApp), findsOneWidget);
  });

  testWidgets('Android folder chooser can bypass the picker for Downloads', (
    WidgetTester tester,
  ) async {
    var selectedPath = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      final result = await selectSharedFolderPath(
                        context,
                        isAndroidOverride: true,
                        pickDirectory: () async => '/picked/folder',
                        folderExistsOverride: (path) =>
                            path == androidDownloadsFolderPath ||
                            path == androidDocumentsFolderPath,
                      );
                      setState(() {
                        selectedPath = result ?? '';
                      });
                    },
                    child: const Text('Pick folder'),
                  ),
                  Text(selectedPath, key: const ValueKey('selected-path')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pick folder'));
    await tester.pumpAndSettle();

    expect(find.text('Choose another folder'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Pictures'), findsOneWidget);
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    expect(find.text(androidDocumentsFolderPath), findsOneWidget);
  });
}
