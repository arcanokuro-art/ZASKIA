import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../settings/app_settings.dart';
import 'model_storage.dart';
import 'resumable_transfer.dart';

class ModelDownload {
  ModelDownload(this.repo, this.revision, this.metadata);
  final String repo, revision;
  final Map<String,dynamic> metadata;
  String get name => metadata['rfilename'] as String;
  String get id => '$repo/$revision/$name';
  String status = 'En cola', error = '', destination = '';
  double? progress;
  int received = 0;
  int? total;
  double bytesPerSecond = 0;
  bool cancelled = false, finished = false, running = false, paused = false;
  ResumableTransfer? transfer;
  Map<String,dynamic> toJson() => {'repo':repo,'revision':revision,'metadata':metadata,
    'destination':destination,'finished':finished,'status':status,'error':error,'received':received,'total':total};
}
class DownloadManager extends ChangeNotifier {
  DownloadManager({this.stateFile, AppSettings? settings, this.root}) : settings = settings ?? AppSettings.instance {
    this.settings.addListener(_pump);
  }
  static final instance = DownloadManager();
  final AppSettings settings;
  final File? stateFile;
  final Directory? root;
  final tasks = <ModelDownload>[];
  bool _initialized = false;
  Future<void> _writes = Future.value();
  int get activeCount => tasks.where((t)=>t.running).length;
  bool get busy => tasks.any((t)=>!t.finished);
  Future<File> _state() async => stateFile ?? File('${(await getApplicationSupportDirectory()).path}/downloads.json');
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final f = await _state();
    if (!await f.exists()) return;
    try {
      for (final raw in jsonDecode(await f.readAsString()) as List) {
        final t = ModelDownload(raw['repo'] as String, raw['revision'] as String, Map<String,dynamic>.from(raw['metadata'] as Map));
        _validate(t);
        t.destination = raw['destination'] as String? ?? '';
        t.finished = raw['finished'] == true;
        t.status = t.finished ? raw['status'] as String : 'Pausada';
        t.error = raw['error'] as String? ?? '';
        t.paused = !t.finished;
        t.received=(raw['received'] as num? ?? 0).toInt();t.total=(raw['total'] as num?)?.toInt();
        if(t.total!=null&&t.total!>0)t.progress=t.received/t.total!;
        if (t.destination.isNotEmpty && await File('${t.destination}.part').exists()) t.received = await File('${t.destination}.part').length();
        tasks.add(t);
      }
    } catch (_) { /* A damaged queue must never prevent launching the app. */ }
    notifyListeners();
  }
  static void _validate(ModelDownload t) {
    if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(t.repo) || !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(t.revision) ||
        t.name.split('/').any((p)=>p.isEmpty || p=='.' || p=='..' || p.contains('\\')) || t.name.startsWith('/')) {
      throw const FormatException('Ruta de descarga no válida.');
    }
  }
  Future<void> _persist() {
    final data = jsonEncode(tasks.map((t)=>t.toJson()).toList());
    final operation = _writes.then((_) async {
      final f = await _state(); await f.parent.create(recursive:true);
      final tmp = File('${f.path}.tmp'); await tmp.writeAsString(data,flush:true); await tmp.rename(f.path);
    });
    _writes = operation.catchError((Object _) {}); return operation;
  }
  Future<void> enqueue(String repo, String revision, Map<String,dynamic> metadata) async {
    await initialize();
    final task = ModelDownload(repo,revision,metadata); _validate(task);
    if (tasks.any((t)=>t.id==task.id && !t.finished)) return;
    final folder = root ?? await ModelStorage.root();
    task.destination = '${folder.path}/${repo.replaceAll('/','--')}/$revision/${task.name}';
    tasks.add(task); await _persist(); notifyListeners(); _pump();
  }
  void pause(ModelDownload t) { if(t.finished)return; t.paused=true; t.status='Pausada'; t.transfer?.stop(); unawaited(_persist()); notifyListeners(); }
  void pauseAll() { for(final t in tasks.where((t)=>!t.finished)) { pause(t); } }
  void resume(ModelDownload t) { if(t.running||tasks.any((other)=>!identical(other,t)&&other.id==t.id&&!other.finished))return; t.paused=false; t.cancelled=false; t.finished=false; t.error=''; t.status='En cola'; unawaited(_persist()); _pump(); notifyListeners(); }
  void cancel(ModelDownload t) { t.cancelled=true; t.paused=false; t.transfer?.stop(); if(!t.running){t.finished=true;t.status='Cancelada';unawaited(File('${t.destination}.part').delete().catchError((Object _) => File('${t.destination}.part')));} unawaited(_persist()); notifyListeners(); }
  void cancelAll() { for(final t in tasks.where((t)=>!t.finished)){cancel(t);} }
  Future<void> remove(ModelDownload t) async { if(t.running || !t.finished)return; tasks.remove(t); await _persist(); notifyListeners(); }
  void _pump() {
    if(!settings.get<bool>('allowNetwork')) { pauseAll(); return; }
    while(activeCount<settings.get<int>('maxDownloads')) {
      final t=tasks.where((t)=>!t.running&&!t.finished&&!t.paused&&!tasks.any((other)=>other.running&&other.id==t.id)).firstOrNull;
      if(t==null)break;
      t.running=true; unawaited(_download(t));
    }
  }
  Future<void> _download(ModelDownload t) async {
    final partial=File('${t.destination}.part');
    final transfer=ResumableTransfer(); t.transfer=transfer;
    var last=DateTime.now(); var prior=t.received;
    try {
      t.status='Descargando…'; notifyListeners();
      final lfs=t.metadata['lfs'] as Map?;
      await transfer.fetch(Uri.https('huggingface.co','/${t.repo}/resolve/${t.revision}/${t.name}'),partial,
        expectedSize:(t.metadata['size'] as num? ?? lfs?['size'] as num?)?.toInt(),
        sha:lfs?['sha256'] as String?,gguf:t.name.toLowerCase().endsWith('.gguf'),
        progress:(n,total){t.received=n;t.total=total;t.progress=total==null?null:n/total;
          final now=DateTime.now();final ms=now.difference(last).inMilliseconds;
          if(ms>=300){t.bytesPerSecond=((n-prior)*1000/ms).clamp(0,double.infinity).toDouble();prior=n;last=now;notifyListeners();}});
      if(t.cancelled||t.paused)return;
      await partial.rename(t.destination); t.received=await File(t.destination).length(); t.total=t.received; t.finished=true;t.status='Guardado';t.progress=1;
    } catch(e) {
      if(!t.paused&&!t.cancelled){t.error=e.toString();t.status='Error';t.finished=true;}
    } finally {
      t.running=false;t.transfer=null;t.bytesPerSecond=0;
      if(t.cancelled){t.finished=true;t.status='Cancelada';if(await partial.exists())await partial.delete();}
      if(t.paused)t.status='Pausada';
      await _persist();notifyListeners();_pump();
    }
  }
  @override
  void dispose(){settings.removeListener(_pump);for(final t in tasks){t.transfer?.stop();}super.dispose();}
}
