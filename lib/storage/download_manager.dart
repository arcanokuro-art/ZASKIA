import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../settings/app_settings.dart';
import '../diagnostics/diagnostic_log.dart';
import 'model_storage.dart';

class ModelDownload {
  ModelDownload(this.repo,this.revision,this.metadata);
  final String repo,revision;
  final Map<String,dynamic> metadata;
  String get name=>metadata['rfilename'] as String;
  String get id=>'$repo/$revision/$name';
  String status='En cola';
  double? progress;
  bool cancelled=false,finished=false,running=false;
  HttpClient? client;
}
class DownloadManager extends ChangeNotifier {
  DownloadManager(){AppSettings.instance.addListener(_pump);}
  static final instance=DownloadManager();
  final tasks=<ModelDownload>[];
  int get activeCount=>tasks.where((t)=>t.running).length;
  bool get busy=>tasks.any((t)=>!t.finished);
  void enqueue(String repo,String revision,Map<String,dynamic> metadata){
    final task=ModelDownload(repo,revision,metadata);
    if(tasks.any((t)=>t.id==task.id&&!t.finished))return;
    tasks.add(task);notifyListeners();_pump();
  }
  void cancel(ModelDownload task){task.cancelled=true;task.client?.close(force:true);if(!task.running){task.finished=true;task.status='Cancelada';}notifyListeners();}
  void cancelAll(){for(final task in tasks.where((t)=>!t.finished)){cancel(task);}}
  void _pump(){
    final settings=AppSettings.instance;
    if(!settings.get<bool>('allowNetwork')) {cancelAll();return;}
    while(activeCount<settings.get<int>('maxDownloads')){
      final task=tasks.where((t)=>!t.running&&!t.finished).firstOrNull;
      if(task==null)break;
      task.running=true;unawaited(_download(task));
    }
  }
  Future<void> _download(ModelDownload task)async{
    File? partial;IOSink? sink;
    try{
      final root=await ModelStorage.root();
      final folder=await Directory('${root.path}/${task.repo.replaceAll('/','--')}/${task.revision}').create(recursive:true);
      final destination=File('${folder.path}/${task.name.split('/').last}');
      partial=File('${destination.path}.part');
      if(task.cancelled)return;
      final client=HttpClient()..connectionTimeout=const Duration(seconds:15);task.client=client;
      final request=await client.getUrl(Uri.https('huggingface.co','/${task.repo}/resolve/${task.revision}/${task.name}'));
      final response=await request.close().timeout(const Duration(seconds:45));
      if(response.statusCode!=200)throw HttpException('HTTP ${response.statusCode}');
      sink=partial.openWrite();var received=0;var last=DateTime.now();
      task.status='Descargando…';notifyListeners();
      await for(final chunk in response.timeout(const Duration(minutes:2))){
        if(task.cancelled)throw StateError('cancelled');
        sink.add(chunk);received+=chunk.length;
        if(DateTime.now().difference(last).inMilliseconds>300){
          await sink.flush();last=DateTime.now();task.progress=response.contentLength>0?received/response.contentLength:null;notifyListeners();
        }
      }
      await sink.close();sink=null;
      if(task.cancelled)throw StateError('cancelled');
      if(response.contentLength>=0&&received!=response.contentLength)throw const FormatException('Incomplete');
      final file=await partial.open();
      try{if(String.fromCharCodes(await file.read(4))!='GGUF')throw const FormatException('GGUF');}finally{await file.close();}
      await partial.rename(destination.path);task.progress=1;task.status='Guardado';
    }catch(e){task.status=task.cancelled?'Cancelada':'No se pudo descargar.';if(!task.cancelled)await DiagnosticLog.record('download',e);}
    finally{
      await sink?.close();task.client?.close(force:true);task.client=null;
      if(partial!=null&&await partial.exists())await partial.delete();
      task.running=false;task.finished=true;if(task.cancelled)task.status='Cancelada';notifyListeners();_pump();
    }
  }
}
