import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/chat/chat_screen.dart';
import 'package:zaskia/platform/android_tablet.dart';

void tablet(WidgetTester tester, Size window, {Size? display}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = window;
  tester.view.display.devicePixelRatio = 1;
  tester.view.display.size = display ?? window;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.display.reset);
}

void main() {
  testWidgets('opens the chat and shows the five attachment actions', (tester) async {
    tablet(tester, const Size(800, 900));
    await tester.pumpWidget(const MaterialApp(home: AndroidTablet(child: ChatScreen())));
    await tester.pumpAndSettle();
    expect(find.text('¿En qué te ayudo?'), findsOneWidget);
    await tester.tap(find.byTooltip('Adjuntar o elegir herramienta'));
    await tester.pumpAndSettle();
    for (final label in ['Cámara', 'Fotos', 'Archivos', 'Crear imagen', 'Editar imagen']) {
      expect(find.descendant(of: find.byWidgetPredicate((widget) => widget is PopupMenuItem), matching: find.text(label)), findsOneWidget);
    }
    expect(find.text('Complementos'), findsNothing);
  });

  testWidgets('shows a submitted message and the model status', (tester) async {
    tablet(tester, const Size(800, 900));
    await tester.pumpWidget(const MaterialApp(home: AndroidTablet(child: ChatScreen())));
    await tester.enterText(find.byType(TextField), 'Hola, ZASKIA');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(find.text('Hola, ZASKIA'), findsOneWidget);
    expect(find.text('Modelo local sin configurar'), findsOneWidget);
  });
  testWidgets('switches sidebar on resize and preserves the draft', (tester) async {
    tablet(tester, const Size(1200, 800));
    await tester.pumpWidget(const MaterialApp(home: AndroidTablet(child: ChatScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.byTooltip('Abrir menú'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Borrador');
    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsNothing);
    expect(find.text('Borrador'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir menú'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget);
  });

  testWidgets('shows the tablet requirement on a phone display', (tester) async {
    tablet(tester, const Size(400, 850));
    await tester.pumpWidget(const MaterialApp(home: AndroidTablet(child: ChatScreen())));
    expect(find.textContaining('diseñada para tablets Android'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('Linux accepts a narrow desktop window and hides Android camera', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tablet(tester, const Size(500, 800));
    await tester.pumpWidget(const MaterialApp(home: AndroidTablet(child: ChatScreen())));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byTooltip('Adjuntar o elegir herramienta'));
    await tester.pumpAndSettle();
    expect(find.text('Cámara'), findsNothing);
    expect(find.text('Archivos'), findsOneWidget);
  });

}
