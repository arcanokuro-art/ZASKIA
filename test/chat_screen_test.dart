import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/main.dart';

void main() {
  testWidgets('opens the chat and shows the five attachment actions', (tester) async {
    await tester.pumpWidget(const ZaskiaApp());
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
    await tester.pumpWidget(const ZaskiaApp());
    await tester.enterText(find.byType(TextField), 'Hola, ZASKIA');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(find.text('Hola, ZASKIA'), findsOneWidget);
    expect(find.text('Modelo local sin configurar'), findsOneWidget);
  });
}
