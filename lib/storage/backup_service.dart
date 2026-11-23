import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../settings/app_settings.dart';
import '../workspace/project_store.dart';
import '../diagnostics/diagnostic_log.dart';

class BackupService {
  static const limit = 64 * 1024 * 1024;
  static bool _working = false;
  static Timer? _timer;
  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes:1), (_) => scheduled());
    unawaited(scheduled());
  }
  static Future<void> scheduled() async {
    final s = AppSettings.instance;
    final hours = s.get<int>('backupHours');
    final folder = s.get<String>('backupFolder');
    if (_working || hours == 0 || folder.isEmpty || DateTime.now().millisecondsSinceEpoch-s.get<int>('lastBackup')<hours*3600000) return;
    try {
      final path = '$folder/ZASKIA-${DateTime.now().millisecondsSinceEpoch}.zaskia';
      await export(path);
      await s.set('lastBackup',DateTime.now().millisecondsSinceEpoch);
    } catch (e) { await DiagnosticLog.record('scheduled-backup',e); }
  }
  static Future<void> export(String path, {ProjectStore? projectStore}) async {
    if (_working) throw StateError('Hay un respaldo en curso.');
    _working = true;
    try {
      final projects = await (projectStore ?? ProjectStore()).list();
      final attachments = <String,String>{};
      var bytes = 0;
      for (final p in projects) {
        final data = p.data;
        final lists = <List>[data['attachments'] as List? ?? [],data['references'] as List? ?? [],
          for (final m in data['messages'] as List? ?? []) (m as Map)['attachments'] as List? ?? []];
        for (final list in lists) {
          for (final item in list) {
            final original = (item as Map)['path'] as String?;
            if (original == null || attachments.containsKey(original)) continue;
            final file = File(original);
            if (!await file.exists()) continue;
            bytes += await file.length();
            if (bytes>limit~/2) throw StateError('El respaldo supera el límite de 32 MB de adjuntos.');
            attachments[original] = base64Encode(await file.readAsBytes());
          }
        }
      }
      final encoded = utf8.encode(jsonEncode({'format':'ZASKIA-1','settings':AppSettings.instance.snapshot,
        'projects':[for(final p in projects) {'name':p.name,'data':p.data,'options':p.options}], 'files':attachments}));
      if (encoded.length>limit) throw StateError('El respaldo supera 64 MB.');
      final target = File(path);
      final tmp = File('$path.tmp');
      await tmp.writeAsBytes(gzip.encode(encoded),flush:true);
      await tmp.rename(target.path);
    } finally { _working = false; }
  }
  static Future<int> restore(String path, {bool settings = false, ProjectStore? projectStore, Directory? temporaryDirectory}) async {
    if (_working) throw StateError('Hay un respaldo en curso.');
    _working = true;
    final created = <String>[];
    final store = projectStore ?? ProjectStore();
    Directory? scratch;
    try {
      final source = File(path);
      if (await source.length()>limit) throw const FormatException('Respaldo demasiado grande.');
      final bytes = <int>[];
      await for (final chunk in gzip.decoder.bind(source.openRead())) {
        if (bytes.length+chunk.length>limit) throw const FormatException('Respaldo demasiado grande.');
        bytes.addAll(chunk);
      }
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;
      if (payload['format']!='ZASKIA-1') throw const FormatException('Formato de respaldo desconocido.');
      final projects = (payload['projects'] as List).cast<Map<String,dynamic>>();
      if (projects.length>1000) throw const FormatException('Demasiadas conversaciones.');
      final files = (payload['files'] as Map<String,dynamic>).map((k,v)=>MapEntry(k,base64Decode(v as String)));
      scratch = await (temporaryDirectory ?? await getTemporaryDirectory()).createTemp('zaskia-restore-');
      for (final entry in projects) {
        if(entry['name'] is! String || entry['data'] is! Map)throw const FormatException('Invalid conversation');
        final p = await store.create(entry['name'] as String);
        created.add(p.id);
        final paths = <String,String>{};
        final data = Map<String,dynamic>.from(entry['data'] as Map);
        Future<List<dynamic>> restoreItems(dynamic value) async {
          final list = <dynamic>[];
          for(final raw in value as List? ?? []) {
            final item = Map<String,dynamic>.from(raw as Map);
            if(item['name'] is! String || item['path'] is! String || item['image'] is! bool)throw const FormatException('Invalid attachment');
            final old = item['path'] as String;
            final content = files[old];
            if(content==null) continue;
            if(!paths.containsKey(old)) {
              final f = File('${scratch!.path}/content');
              await f.writeAsBytes(content);
              paths[old] = await store.copyAttachment(p.id,f.path);
            }
            item['path']=paths[old]; list.add(item);
          }
          return list;
        }
        data['attachments']=await restoreItems(data['attachments']);
        data['references']=await restoreItems(data['references']);
        for(final message in data['messages'] as List? ?? []) {
          (message as Map)['attachments']=await restoreItems(message['attachments']);
        }
        await store.save(Project(p.id,p.name,DateTime.now().millisecondsSinceEpoch,data,
          options:{for(final o in Map<String,dynamic>.from(entry['options'] as Map? ?? {}).entries)
            if((['pinned','archived','locked'].contains(o.key)&&o.value is bool)||(o.key=='folder'&&o.value is String))o.key:o.value}));
      }
      if(settings) {
        final saved = AppSettings.validate(Map<String,dynamic>.from(payload['settings'] as Map));
        // Device paths and schedules must be explicitly chosen on the destination.
        for(final key in ['modelFolder','backupFolder','backupHours','lastProject','lastBackup']) { saved.remove(key); }
        await AppSettings.instance.update(saved);
      }
      return created.length;
    } catch (_) {
      for(final id in created) { await store.remove(id); }
      rethrow;
    } finally {
      if(scratch!=null) await scratch.delete(recursive:true);
      _working=false;
    }
  }
}
