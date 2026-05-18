import 'package:flutter/material.dart';

/// Application theme definitions for light and dark modes.
class AppTheme {
  static const Color _lightSeedColor = Color(0xFF1565C0);
  static const Color _darkSeedColor = Color(0xFF4A9EFF);

  /// Light theme configuration.
  static ThemeData get lightTheme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _lightSeedColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  /// Dark theme configuration.
  static ThemeData get darkTheme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _darkSeedColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}

/// File type icon colors optimized for both light and dark themes.
class FileTypeColors {
  // Folder color
  static const Color folderLight = Color(0xFFFFA000);
  static const Color folderDark = Color(0xFFFFB74D);

  // Image color
  static const Color imageLight = Color(0xFF9C27B0);
  static const Color imageDark = Color(0xFFBA68C8);

  // Video color
  static const Color videoLight = Color(0xFFE53935);
  static const Color videoDark = Color(0xFFEF5350);

  // Audio color
  static const Color audioLight = Color(0xFF43A047);
  static const Color audioDark = Color(0xFF66BB6A);

  // PDF color
  static const Color pdfLight = Color(0xFFF4511E);
  static const Color pdfDark = Color(0xFFFF7043);

  // Archive color
  static const Color archiveLight = Color(0xFF795548);
  static const Color archiveDark = Color(0xFFA1887F);

  // Code color
  static const Color codeLight = Color(0xFF00ACC1);
  static const Color codeDark = Color(0xFF4DD0E1);

  // Text/Markdown color
  static const Color textLight = Color(0xFF1E88E5);
  static const Color textDark = Color(0xFF64B5F6);

  // Document color
  static const Color documentLight = Color(0xFF1565C0);
  static const Color documentDark = Color(0xFF42A5F5);

  // Spreadsheet color
  static const Color spreadsheetLight = Color(0xFF2E7D32);
  static const Color spreadsheetDark = Color(0xFF81C784);

  // Presentation color
  static const Color presentationLight = Color(0xFFE65100);
  static const Color presentationDark = Color(0xFFFF8A65);

  // Generic file color
  static const Color genericLight = Color(0xFF607D8B);
  static const Color genericDark = Color(0xFF90A4AE);

  /// Get the appropriate color for the given brightness.
  static Color getColor(Color light, Color dark, Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }
}
