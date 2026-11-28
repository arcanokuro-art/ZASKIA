import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../hardware/hardware_snapshot.dart';
import '../hardware/hardware_advisor.dart';

class AppSettings extends ChangeNotifier {
  AppSettings({this.file});
  static final instance = AppSettings();
  final File? file;
  static const defaults = <String, dynamic>{
    'onboardingComplete': false, 'language': 'es', 'theme': 'system', 'textScale': 1.0, 'compact': false,
    'contrast': false, 'reduceMotion': false, 'modelFolder': '', 'modelFolders':<dynamic>[], 'backupFolder': '',
    'threads': 4, 'context': 2048, 'maxTokens': 512, 'temperature': 0.7,
    'historyTurns': 20, 'requestTimeoutSeconds': 180, 'showGenerationStats': true,
    'comfyAddress': 'http://127.0.0.1:8188', 'voiceAddress': 'http://127.0.0.1:8080',
    'speechModel': '', 'transcriptionModel': '', 'voiceName': 'alloy',
    'idleMinutes': 10, 'backgroundWork': false, 'systemPrompt': '',
    'responseLanguage': 'auto', 'enterSends': false, 'remember': false, 'memory': '',
    'startup': 'last', 'lastProject': '', 'autoLoad': false,
    'allowNetwork': true, 'allowAttachments': true, 'largeDownloadMB': 1000,
    'maxDownloads':1, 'backupHours': 0, 'lastBackup': 0, 'profile': 'balanced', 'customProfiles': <dynamic>[],
  };
  Map<String, dynamic> _data = Map.of(defaults);
  Future<void> _writes = Future.value();
  String? error;
  bool freshInstall=false;
  T get<T>(String key) => _data[key] as T;
  Map<String, dynamic> get snapshot => jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
  Future<File> _file() async => file ?? File('${(await getApplicationSupportDirectory()).path}/settings.json');
  Future<void> load() async {
    try {
      final target = await _file();
      freshInstall=!await target.exists();
      if (!freshInstall) _data = validate(jsonDecode(await target.readAsString()) as Map<String, dynamic>);
    } catch (_) { error = 'No se pudo leer la configuración.'; }
    notifyListeners();
  }
  Future<void> initializeHardwareDefaults({HardwareSnapshot? hardware})async {
    if(!freshInstall)return;
    final snapshot=hardware??await HardwareProbe.read();
    await update(HardwareAdvisor.recommend(snapshot).settings);
    freshInstall=false;
  }
  static Map<String, dynamic> validate(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.of(defaults);
    for (final key in defaults.keys) {
      final v = input[key], d = defaults[key];
      if (v != null && (d is num ? v is num : d is List ? v is List : v.runtimeType == d.runtimeType)) result[key] = v;
    }
    for (final entry in <String, List<num>>{'threads':[1,64], 'context':[512,32768], 'maxTokens':[32,8192],
      'temperature':[0,2], 'textScale':[0.8,1.8], 'idleMinutes':[0,120], 'backupHours':[0,168],
      'historyTurns':[1,100], 'requestTimeoutSeconds':[30,1800], 'maxDownloads':[1,3], 'largeDownloadMB':[100,20000], 'lastBackup':[0,9000000000000000]}.entries) {
      final value = (result[entry.key] as num).clamp(entry.value[0], entry.value[1]);
      result[entry.key] = ['temperature','textScale'].contains(entry.key) ? value.toDouble() : value.toInt();
    }
    if (!['es','en','zh','ko','ja','fr'].contains(result['language'])) result['language'] = 'es';
    if (!['system','light','dark'].contains(result['theme'])) result['theme'] = 'system';
    if (!['last','new'].contains(result['startup'])) result['startup'] = 'last';
    if (!['auto','es','en','zh','ko','ja','fr'].contains(result['responseLanguage'])) result['responseLanguage'] = 'auto';
    result['modelFolders']=(result['modelFolders'] as List).whereType<String>().where((p)=>p.isNotEmpty).toSet().toList();
    final profiles = result['customProfiles'] as List;
    result['customProfiles'] = [for(final p in profiles.take(50))
      if(p is Map && p['name'] is String && p['values'] is Map)
        {'name':(p['name'] as String).substring(0,(p['name'] as String).length.clamp(0,60).toInt()),
         'values':{for(final k in ['threads','context','maxTokens','temperature','systemPrompt','idleMinutes'])
           if((p['values'] as Map).containsKey(k)) k:(p['values'] as Map)[k]}}];
    for(final key in ['memory','systemPrompt']) {
      final value=result[key] as String;
      if(value.length>8000)result[key]=value.substring(0,8000);
    }
    return result;
  }
  Future<void> set(String key, dynamic value) => update({key:value});
  Future<void> update(Map<String, dynamic> changes) {
    final next = validate({..._data, ...changes});
    final operation = _writes.then((_) async {
      final target = await _file();
      await target.parent.create(recursive:true);
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(jsonEncode(next), flush:true);
      await tmp.rename(target.path);
    });
    _writes = operation.then<void>((_) {}, onError:(Object e, StackTrace s) {});
    _data = next;
    notifyListeners();
    return operation;
  }
  Future<void> reset(Iterable<String> keys) => update({for (final k in keys) k:defaults[k]});
  Future<void> profile(String id) => update(switch(id) {
    'economy' => {'profile':id,'threads':2,'context':1024,'maxTokens':256,'idleMinutes':3},
    'creative' => {'profile':id,'temperature':1.0,'systemPrompt':'Help with creative writing.','maxTokens':1024},
    'code' => {'profile':id,'temperature':0.2,'systemPrompt':'Help with programming. Explain and verify your assumptions.','maxTokens':1024},
    _ => {'profile':'balanced','threads':4,'context':2048,'maxTokens':512,'temperature':0.7,'systemPrompt':'','idleMinutes':10},
  });
  ThemeMode get themeMode => switch(get<String>('theme')) {'light'=>ThemeMode.light,'dark'=>ThemeMode.dark,_=>ThemeMode.system};
}
