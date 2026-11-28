import 'dart:async';
import 'engines/engine_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'settings/app_settings.dart';
import 'storage/backup_service.dart';
import 'storage/download_manager.dart';

import 'onboarding/start_screen.dart';
import 'platform/android_tablet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  try {await AppSettings.instance.initializeHardwareDefaults();}catch(_){}
  await DownloadManager.instance.initialize();
  WidgetsBinding.instance.addObserver(_EngineLifetime());
  runApp(const ZaskiaApp());
  BackupService.start();
}

class ZaskiaApp extends StatelessWidget {
  const ZaskiaApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: AppSettings.instance, builder:(context,_)=>MaterialApp(
    title: 'ZASKIA',
    locale: Locale(AppSettings.instance.get<String>('language')),
    supportedLocales: const [Locale('es'),Locale('en'),Locale('zh'),Locale('ko'),Locale('ja'),Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    themeMode: AppSettings.instance.themeMode,
    themeAnimationDuration: AppSettings.instance.get<bool>('reduceMotion') ? Duration.zero : const Duration(milliseconds:200),
    builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(
      textScaler:TextScaler.linear(MediaQuery.textScalerOf(context).scale(AppSettings.instance.get<double>('textScale'))),
      disableAnimations:AppSettings.instance.get<bool>('reduceMotion'),
      highContrast:AppSettings.instance.get<bool>('contrast'),
    ),child:child!),
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const AndroidTablet(child: StartScreen()),
  ));

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF101010) : Colors.white;
    final foreground = dark ? Colors.white : const Color(0xFF151515);
    final muted = AppSettings.instance.get<bool>('contrast') ? foreground : dark ? const Color(0xFFB3B3B3) : const Color(0xFF616161);
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

class _EngineLifetime extends WidgetsBindingObserver {
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.detached)unawaited(EngineManager.instance.stopAll());
  }
}
