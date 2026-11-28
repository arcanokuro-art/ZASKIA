import 'dart:io';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:zaskia/onboarding/start_screen.dart';
import 'package:zaskia/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/onboarding/onboarding_screen.dart';
import 'package:zaskia/hardware/hardware_snapshot.dart';
class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override Future<String?> getApplicationSupportPath()async=>path;
  @override Future<String?> getTemporaryPath()async=>path;
}
void main(){
  testWidgets('finishing the first-run gate opens the actual chat without a restart',(tester)async{
    final root=(await tester.runAsync(()=>Directory.systemTemp.createTemp()))!;final prior=PathProviderPlatform.instance;
    PathProviderPlatform.instance=_Paths(root.path);
    addTearDown(()async{PathProviderPlatform.instance=prior;await root.delete(recursive:true);});
    await tester.runAsync(()=>AppSettings.instance.set('onboardingComplete',false));
    await tester.pumpWidget(const MaterialApp(home:StartScreen()));await tester.pumpAndSettle();
    await tester.tap(find.text('Configurar después'));await tester.pump();
    for(var i=0;i<50 && find.text('¿En qué te ayudo?').evaluate().isEmpty;i++){
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
      await tester.pump();
    }
    expect(AppSettings.instance.get<bool>('onboardingComplete'),true);
    expect(find.text('¿En qué te ayudo?'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('first start explains optional weights and permits deferring setup',(tester)async{
    var completed=false;
    await tester.pumpWidget(MaterialApp(home:OnboardingScreen(onFinished:()async{completed=true;},probe:()async=>HardwareSnapshot(os:'android',abi:'android_arm64',logicalCores:8,usableCores:8,capturedAt:DateTime(2026),totalMemory:4*1073741824))));
    await tester.pumpAndSettle();expect(find.text('Tu primera IA, paso a paso'),findsOneWidget);
    expect(find.text('Elegirás el modelo antes de descargar. No se instala ningún peso automáticamente.'),findsOneWidget);
    await tester.tap(find.text('Configurar después'));await tester.pumpAndSettle();expect(completed,true);
  });
}
