import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await _requestStoragePermissions();
  }
  runApp(const OpenFoldrApp());
}

Future<void> _requestStoragePermissions() async {
  // Android 11+ (API 30+): request broad external storage management.
  if (await Permission.manageExternalStorage.isDenied) {
    await Permission.manageExternalStorage.request();
  }
  // Android ≤10 fallback.
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }
}
