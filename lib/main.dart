import 'package:flutter/material.dart';

import 'workspace/projects_screen.dart';
import 'platform/android_tablet.dart';

void main() => runApp(const ZaskiaApp());

class ZaskiaApp extends StatelessWidget {
  const ZaskiaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ZASKIA',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const AndroidTablet(child: ProjectsScreen()),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF101010) : Colors.white;
    final foreground = dark ? Colors.white : const Color(0xFF151515);
    final muted = dark ? const Color(0xFFB3B3B3) : const Color(0xFF616161);
    final panel = dark ? const Color(0xFF1D1D1D) : const Color(0xFFF3F3F3);
    final bubble = dark ? const Color(0xFF292929) : const Color(0xFFEAEAEA);
    final colors = ColorScheme(
      brightness: brightness,
      primary: foreground,
      onPrimary: background,
      secondary: foreground,
      onSecondary: background,
      secondaryContainer: bubble,
      onSecondaryContainer: foreground,
      error: foreground,
      onError: background,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainer: panel,
      surfaceContainerHighest: bubble,
      outline: muted,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: background),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: muted),
      ),
    );
  }
}
