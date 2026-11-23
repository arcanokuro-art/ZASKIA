import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:zaskia/settings/app_settings.dart';
import 'package:zaskia/settings/settings_screen.dart';
import 'package:zaskia/runtime/model_runtime.dart';
import 'package:zaskia/runtime/downloaded_models.dart';
import 'package:zaskia/storage/model_storage.dart';

class TestPaths extends PathProviderPlatform {
  TestPaths(this.path);
  final String path;
  @override Future<String?> getApplicationSupportPath()async=>path;
  @override Future<String?> getTemporaryPath()async=>path;
}
void main(){
  testWidgets('settings start in Spanish and update labels live in each language', (tester)async{
    final directory=(await tester.runAsync(()=>Directory.systemTemp.createTemp('zaskia-settings-ui-')))!;
    final previous=PathProviderPlatform.instance;
    PathProviderPlatform.instance=TestPaths(directory.path);
    addTearDown(()async{
      await tester.runAsync(()async{
      await AppSettings.instance.update(AppSettings.defaults);
      PathProviderPlatform.instance=previous;
      await directory.delete(recursive:true);
      });
    });
    await tester.pumpWidget(MaterialApp(home:SettingsScreen(runtime:ModelRuntime())));
    expect(find.text('Configuración'),findsOneWidget);
    for(final entry in {'en':'Settings','zh':'设置','ko':'설정','ja':'設定','fr':'Paramètres'}.entries){
      await tester.runAsync(()=>AppSettings.instance.set('language',entry.key));
      await tester.pump();
      expect(find.text(entry.value),findsOneWidget);
    }
    await tester.runAsync(()=>AppSettings.instance.set('language','es'));
    await tester.enterText(find.byType(TextField).first,'CPU');
    await tester.pump();
    expect(find.text('Rendimiento y energía'),findsOneWidget);
    expect(find.text('Apariencia'),findsNothing);
    await tester.runAsync(()async{
      final a=await Directory('${directory.path}/models-a').create();
      final b=await Directory('${directory.path}/models-b').create();
      await File('${a.path}/first.gguf').writeAsString('GGUF');
      await File('${b.path}/second.gguf').writeAsString('GGUF');
      await AppSettings.instance.update({'modelFolder':b.path,'modelFolders':[a.path,b.path]});
      final files=await DownloadedModels().list();
      expect(files.map((f)=>f.path),containsAll(['${a.path}/first.gguf','${b.path}/second.gguf']));
      final partial=File('${b.path}/imports/model-test/model.gguf.part');
      await partial.parent.create(recursive:true);await partial.writeAsString('partial');
      final unrelated=await File('${b.path}/unrelated.part').writeAsString('keep');
      expect(await ModelStorage.clearPartial(),1);
      expect(await partial.exists(),false);expect(await unrelated.exists(),true);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
