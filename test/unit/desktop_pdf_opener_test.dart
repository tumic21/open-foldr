import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/ui/screens/guest/desktop_pdf_opener.dart';

void main() {
  group('buildDesktopOpenCommand', () {
    test('uses xdg-open on Linux', () {
      final command = buildDesktopOpenCommand(
        DesktopPdfPlatform.linux,
        '/tmp/example.pdf',
      );

      expect(command.executable, 'xdg-open');
      expect(command.arguments, ['/tmp/example.pdf']);
    });
  });

  group('normalizePdfFileName', () {
    test('preserves a pdf extension', () {
      expect(normalizePdfFileName('guide.pdf'), 'guide.pdf');
    });

    test('adds a pdf extension when missing', () {
      expect(normalizePdfFileName('guide'), 'guide.pdf');
    });
  });

  group('DesktopPdfOpener', () {
    test('writes the file and launches it', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'open_foldr_pdf_test_',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      String? launchedExecutable;
      List<String>? launchedArguments;
      final opener = DesktopPdfOpener(
        platform: DesktopPdfPlatform.linux,
        tempDirectory: tempDirectory,
        processRunner: (executable, arguments) async {
          launchedExecutable = executable;
          launchedArguments = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );

      final outputPath = await opener.openPdf(
        Uint8List.fromList([1, 2, 3]),
        'guide',
      );

      expect(launchedExecutable, 'xdg-open');
      expect(launchedArguments, [outputPath]);
      expect(await File(outputPath).exists(), isTrue);
      expect(await File(outputPath).readAsBytes(), [1, 2, 3]);
      expect(outputPath.endsWith('guide.pdf'), isTrue);
    });

    test('throws when the launcher fails', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'open_foldr_pdf_test_',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final opener = DesktopPdfOpener(
        platform: DesktopPdfPlatform.linux,
        tempDirectory: tempDirectory,
        processRunner: (_, __) async => ProcessResult(0, 1, '', 'missing'),
      );

      await expectLater(
        () => opener.openPdf(Uint8List(0), 'broken.pdf'),
        throwsA(isA<PdfOpenException>()),
      );
    });
  });
}