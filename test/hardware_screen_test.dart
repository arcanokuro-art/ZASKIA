import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/hardware/hardware_snapshot.dart';
import 'package:zaskia/hardware/hardware_screen.dart';
import 'package:zaskia/runtime/model_runtime.dart';
import 'package:zaskia/benchmark/benchmark_store.dart';
import 'package:zaskia/benchmark/benchmark_result.dart';
import 'package:zaskia/localization/strings.dart';
import 'dart:io';

class MemoryBenchmarks extends BenchmarkStore {
  @override Future<List<BenchmarkResult>> list()async=>[];
}
void main(){
  testWidgets('hardware view identifies ARM64 and requires a selected model for testing',(tester)async{
    final h=HardwareSnapshot(os:'android',abi:'android_arm64',logicalCores:8,usableCores:8,
      capturedAt:DateTime(2026),totalMemory:4*1073741824,availableMemory:2*1073741824);
    await tester.pumpWidget(MaterialApp(home:HardwareScreen(runtime:ModelRuntime(),store:MemoryBenchmarks(),probe:()async=>h)));
    await tester.pumpAndSettle();
    expect(find.text('ARM64'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('Iniciar prueba'),500);
    final button=tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Iniciar prueba'));
    expect(button.onPressed,isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('hardware screen labels have translations in all selectable languages',(){
    final source=File('lib/hardware/hardware_screen.dart').readAsStringSync();
    final keys=<String>{};
    for(final pattern in [RegExp(r"S.t\('([^'\n\$]*)'\)"),RegExp(r"_(?:card|row)\('([^']*)'")]){
      keys.addAll(pattern.allMatches(source).map((m)=>m[1]!));
    }
    for(final lang in ['en','zh','ko','ja','fr']){
      for(final key in keys){expect(S.has(lang,key),true,reason:'$lang: $key');}
    }
  });
}
