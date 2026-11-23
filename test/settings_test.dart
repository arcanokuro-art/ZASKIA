import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/settings/app_settings.dart';
import 'package:zaskia/localization/strings.dart';
import 'package:zaskia/updates/update_service.dart';

void main(){
  test('Spanish default, validated preferences persist, profiles affect inference',()async{
    final dir=await Directory.systemTemp.createTemp('zaskia-settings-');
    addTearDown(()=>dir.delete(recursive:true));
    final f=File('${dir.path}/settings.json');
    final settings=AppSettings(file:f);
    expect(settings.get<String>('language'),'es');
    await settings.update({'language':'ja','threads':1000,'context':-20,'temperature':9.0});
    expect(settings.get<int>('threads'),64);expect(settings.get<int>('context'),512);
    expect(settings.get<double>('temperature'),2.0);
    final loaded=AppSettings(file:f);await loaded.load();expect(loaded.get<String>('language'),'ja');
    await loaded.profile('economy');expect(loaded.get<int>('threads'),2);
    expect(loaded.get<int>('context'),1024);
    await loaded.reset(['language']);expect(loaded.get<String>('language'),'es');
  });
  test('all settings labels are translated in five selectable languages',(){
    final content=File('lib/settings/settings_screen.dart').readAsStringSync();
    final labels=<String>{};
    for(final pattern in [RegExp(r"S.t\('([^'\n\$]*)'\)"),
      RegExp(r"_(?:section|action)\('([^']*)'"),
      RegExp(r"_(?:toggle|slider|select|edit)\('[^']*','([^']*)'")]){
      labels.addAll(pattern.allMatches(content).map((m)=>m[1]!));
    }
    for(final lang in ['en','zh','ko','ja','fr']){
      for(final label in labels){expect(S.has(lang,label),true,reason:'$lang: $label');}
    }
  });
  test('semantic updates compare numbers and reject malformed tags',(){
    expect(UpdateService.newer('0.14.0','0.13.0'),true);
    expect(UpdateService.newer('0.9.0','0.13.0'),false);
    expect(UpdateService.newer('v5','0.13.0'),false);
  });
}
