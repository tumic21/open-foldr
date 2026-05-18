import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

class OpenFoldrApp extends StatefulWidget {
  const OpenFoldrApp({super.key});

  static _OpenFoldrAppState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<_OpenFoldrAppState>();
  }

  @override
  State<OpenFoldrApp> createState() => _OpenFoldrAppState();
}

class _OpenFoldrAppState extends State<OpenFoldrApp> {
  static const String _themeModePrefKey = 'ui.theme_mode';
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = prefs.getString(_themeModePrefKey);
    final parsedMode = _parseThemeMode(storedMode);
    if (!mounted || parsedMode == _themeMode) return;
    setState(() {
      _themeMode = parsedMode;
    });
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefKey, _themeModeToString(mode));
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() {
      _themeMode = mode;
    });
    _saveThemeMode(mode);
  }

  ThemeMode _parseThemeMode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _themeModeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Foldr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const HomeScreen(),
    );
  }
}
