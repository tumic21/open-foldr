import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

enum DesktopPdfPlatform { linux, macos, windows, unsupported }

class DesktopOpenCommand {
  final String executable;
  final List<String> arguments;

  const DesktopOpenCommand({
    required this.executable,
    required this.arguments,
  });
}

typedef DesktopProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class DesktopPdfOpener {
  DesktopPdfOpener({
    DesktopPdfPlatform? platform,
    DesktopProcessRunner? processRunner,
    Directory? tempDirectory,
  }) : _platform = platform ?? _detectPlatform(),
       _processRunner = processRunner ?? Process.run,
       _tempDirectory = tempDirectory;

  final DesktopPdfPlatform _platform;
  final DesktopProcessRunner _processRunner;
  final Directory? _tempDirectory;

  Future<String> openPdf(Uint8List bytes, String fileName) async {
    final directory = _tempDirectory ?? await _ensureTempDirectory();
    final normalizedFileName = normalizePdfFileName(fileName);
    final outputPath = p.join(
      directory.path,
      '${DateTime.now().microsecondsSinceEpoch}-$normalizedFileName',
    );

    await File(outputPath).writeAsBytes(bytes, flush: true);

    final command = buildDesktopOpenCommand(_platform, outputPath);
    final result = await _processRunner(command.executable, command.arguments);
    if (result.exitCode != 0) {
      throw const PdfOpenException('Could not open PDF in the system viewer.');
    }

    return outputPath;
  }

  static DesktopPdfPlatform _detectPlatform() {
    if (Platform.isLinux) return DesktopPdfPlatform.linux;
    if (Platform.isMacOS) return DesktopPdfPlatform.macos;
    if (Platform.isWindows) return DesktopPdfPlatform.windows;
    return DesktopPdfPlatform.unsupported;
  }

  Future<Directory> _ensureTempDirectory() async {
    final directory = Directory(
      p.join(Directory.systemTemp.path, 'open_foldr', 'pdf-preview'),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}

DesktopOpenCommand buildDesktopOpenCommand(
  DesktopPdfPlatform platform,
  String filePath,
) {
  switch (platform) {
    case DesktopPdfPlatform.linux:
      return DesktopOpenCommand(
        executable: 'xdg-open',
        arguments: [filePath],
      );
    case DesktopPdfPlatform.macos:
      return DesktopOpenCommand(executable: 'open', arguments: [filePath]);
    case DesktopPdfPlatform.windows:
      return DesktopOpenCommand(
        executable: 'cmd',
        arguments: ['/c', 'start', '', filePath],
      );
    case DesktopPdfPlatform.unsupported:
      throw const PdfOpenException('Desktop PDF opening is unsupported here.');
  }
}

String normalizePdfFileName(String fileName) {
  final baseName = p.basename(fileName.trim());
  if (baseName.isEmpty) return 'document.pdf';
  if (baseName.toLowerCase().endsWith('.pdf')) return baseName;
  return '$baseName.pdf';
}

class PdfOpenException implements Exception {
  final String message;

  const PdfOpenException(this.message);

  @override
  String toString() => message;
}