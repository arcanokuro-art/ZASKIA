import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/onboarding/onboarding_screen.dart';
import 'package:zaskia/hardware/hardware_snapshot.dart';
void main(){
  testWidgets('first start explains optional weights and permits deferring setup',(tester)async{
    var completed=false;
    await tester.pumpWidget(MaterialApp(home:OnboardingScreen(onFinished:()async{completed=true;},probe:()async=>HardwareSnapshot(os:'android',abi:'android_arm64',logicalCores:8,usableCores:8,capturedAt:DateTime(2026),totalMemory:4*1073741824))));
    await tester.pumpAndSettle();expect(find.text('Tu primera IA, paso a paso'),findsOneWidget);
    expect(find.text('Elegirás el modelo antes de descargar. No se instala ningún peso automáticamente.'),findsOneWidget);
    await tester.tap(find.text('Configurar después'));await tester.pumpAndSettle();expect(completed,true);
  });
}
