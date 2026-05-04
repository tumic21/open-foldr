import 'package:flutter/material.dart';
import 'ui/screens/home_screen.dart';

class OpenFoldrApp extends StatelessWidget {
  const OpenFoldrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Foldr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
