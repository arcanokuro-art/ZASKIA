import 'package:flutter/material.dart';

import 'chat_screen.dart';

void main() => runApp(const ZaskiaApp());

class ZaskiaApp extends StatelessWidget {
  const ZaskiaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ZASKIA',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFA6F5DC),
        onPrimary: Color(0xFF06231B),
        surface: Color(0xFF101522),
        onSurface: Color(0xFFF5F7FC),
        onSurfaceVariant: Color(0xFFB5BDCF),
        outline: Color(0xFF4C566C),
      ),
      scaffoldBackgroundColor: const Color(0xFF080C15),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF080C15),
        surfaceTintColor: Colors.transparent,
      ),
    ),
    home: const ChatScreen(),
  );
}
