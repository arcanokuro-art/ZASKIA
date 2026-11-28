import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../settings/app_settings.dart';
import '../hardware/hardware_snapshot.dart';
import '../storage/resumable_transfer.dart';
import '../media/engine_http.dart';

enum EngineKind { ollama, comfy }
class EngineRelease {
  const EngineRelease(this.kind,this.version,this.revision,{this.url,this.sha256,this.bytes});
  final EngineKind kind;
  final String version,revision;
  final String? url,sha256;
  final int? bytes;
}
typedef CommandRun = Future<void> Function(String executable,List<String> arguments,String cwd);

/// Installs in user-owned directories. Switching one JSON pointer publishes an
/// installation; the old environment remains usable if a later install fails.
class EngineManager extends ChangeNotifier {
  EngineManager({this.directory,this.commandRunner,this.supported}) ;
  static final instance=EngineManager();
  final Directory? directory;
  final CommandRun? commandRunner;
  final bool? supported;
  bool get canManage=>supported??(Platform.isLinux&&HardwareProbe.supportsNativeRuntime());
  bool busy=false,cancelled=false;
  String status='',log='';
  Process? _command;
  ResumableTransfer? _transfer;
  final _running=<EngineKind,Process>{};
  final _addresses=<EngineKind,String>{};
  final _clients=<HttpClient>{};
  bool running(EngineKind kind)=>_running.containsKey(kind);
  String address(EngineKind kind)=>_addresses[kind]??(kind==EngineKind.ollama?'http://127.0.0.1:11434':'http://127.0.0.1:8188');
  Future<Directory> root()async=>(directory??Directory('${(await getApplicationSupportDirectory()).path}/engines')).create(recursive:true);
  Future<Directory> _folder(EngineKind kind)async=>Directory('${(await root()).path}/${kind.name}').create(recursive:true);
  Future<Map<String,dynamic>?> installation(EngineKind kind)async{
    final f=File('${(await _folder(kind)).path}/installation.json');
    if(!await f.exists())return null;
    final data=Map<String,dynamic>.from(jsonDecode(await f.readAsString()) as Map);
    final active=data['active'] as Map;
    if(!RegExp(r'^build-[a-zA-Z0-9_-]+$').hasMatch(active['directory'] as String))throw const FormatException('Instalación no válida.');
    return data;
  }
  Future<void> _publish(EngineKind kind,Map<String,dynamic> data)async{
    final root=await _folder(kind);final f=File('${root.path}/installation.json.tmp');
    await f.writeAsString(jsonEncode(data),flush:true);await f.rename('${root.path}/installation.json');
  }
  Future<Map<String,dynamic>> _github(String path)async{
    if(!AppSettings.instance.get<bool>('allowNetwork'))throw StateError('Acceso a red desactivado.');
    final client=HttpClient()..connectionTimeout=const Duration(seconds:15);_clients.add(client);
    try{
      final request=await client.getUrl(Uri.https('api.github.com',path));request.headers.set('User-Agent','ZASKIA');
      final response=await request.close().timeout(const Duration(seconds:30));
      if(response.statusCode!=200)throw HttpException('GitHub: HTTP ${response.statusCode}');
      final body=StringBuffer();var length=0;
      await for(final chunk in response.transform(utf8.decoder).timeout(const Duration(seconds:30))){length+=chunk.length;if(length>8*1024*1024)throw const FormatException('Respuesta demasiado grande.');body.write(chunk);}
      return Map<String,dynamic>.from(jsonDecode(body.toString()) as Map);
    }finally{client.close(force:true);_clients.remove(client);}
  }
  Future<EngineRelease> latest(EngineKind kind)async{
    final repo=kind==EngineKind.ollama?'ollama/ollama':'Comfy-Org/ComfyUI';
    final release=await _github('/repos/$repo/releases/latest');final tag=release['tag_name'] as String;
    if(!RegExp(r'^v?\d+\.\d+\.\d+(?:[.-][a-zA-Z0-9.-]+)?$').hasMatch(tag))throw const FormatException('Versión del motor no válida.');
    if(kind==EngineKind.comfy){final commit=await _github('/repos/$repo/commits/$tag');final sha=commit['sha'] as String;
      if(!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha))throw const FormatException('Revisión no válida.');return EngineRelease(kind,tag,sha);}
    final asset=(release['assets'] as List).cast<Map>().firstWhere((a)=>a['name']=='ollama-linux-amd64.tar.zst');
    final digest=asset['digest'] as String? ?? '';
    if(!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest))throw const FormatException('No hay SHA-256 publicado para este motor.');
    final url=asset['browser_download_url'] as String;
    if(url!='https://github.com/ollama/ollama/releases/download/$tag/ollama-linux-amd64.tar.zst')throw const FormatException('Origen del motor no válido.');
    return EngineRelease(kind,tag,tag,url:url,sha256:digest.substring(7),bytes:(asset['size'] as num).toInt());
  }
  void _update(String value){status=value;notifyListeners();}
  void _append(String value){log+=value;if(log.length>12000)log=log.substring(log.length-12000);notifyListeners();}
  String get _launcher=>'${File(Platform.resolvedExecutable).parent.path}/zaskia-managed-engine';
  Future<void> _run(String executable,List<String> args,String cwd)async{
    if(cancelled)throw StateError('Operación cancelada.');
    if(commandRunner!=null){await commandRunner!(executable,args,cwd);return;}
    var resolved=executable;
    if(!resolved.startsWith('/')){
      for(final path in (Platform.environment['PATH']??'/usr/bin:/bin').split(':')){if(await File('$path/$executable').exists()){resolved='$path/$executable';break;}}
    }
    final packaged=await File(_launcher).exists();
    if(packaged&&!resolved.startsWith('/'))throw ProcessException(executable,args,'Falta un requisito: git, python3-venv o zstd.');
    final p=await Process.start(packaged?_launcher:'setsid',packaged?[resolved,...args]:[executable,...args],workingDirectory:cwd,
      environment:{'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null','PIP_CONFIG_FILE':'/dev/null','PYTHONNOUSERSITE':'1','PIP_NO_INPUT':'1'});
    _command=p;
    final out=p.stdout.transform(utf8.decoder).listen(_append),err=p.stderr.transform(utf8.decoder).listen(_append);
    try{final code=await p.exitCode.timeout(const Duration(minutes:30));if(code!=0)throw StateError('No se completó la instalación. Revisa el registro y los requisitos.');}
    catch(_){await _terminate(p);rethrow;}
    finally{if(identical(_command,p))_command=null;if(cancelled){await _terminate(p);}await out.cancel();await err.cancel();}
  }
  Future<void> install(EngineRelease release)async{
    if(!canManage)throw UnsupportedError('La instalación administrada está disponible en Linux.');
    if(!AppSettings.instance.get<bool>('allowNetwork'))throw StateError('Acceso a red desactivado.');
    if(busy||running(release.kind))throw StateError('Detén el motor y espera la operación actual.');
    busy=true;cancelled=false;log='';Directory? build;
    try{
      final folder=await _folder(release.kind);final previous=await installation(release.kind);
      build=await folder.createTemp('build-');
      if(release.kind==EngineKind.comfy){
        if(!RegExp(r'^[a-f0-9]{40}$').hasMatch(release.revision))throw const FormatException('Revisión no válida.');
        _update('Preparando ComfyUI');
        await _run('git',['init','source'],build.path);
        await _run('git',['remote','add','origin','https://github.com/Comfy-Org/ComfyUI.git'],'${build.path}/source');
        await _run('git',['fetch','--depth','1','origin',release.revision],'${build.path}/source');
        await _run('git',['checkout','--detach','FETCH_HEAD'],'${build.path}/source');
        await _run('python3',['-m','venv','${build.path}/venv'],build.path);
        final python='${build.path}/venv/bin/python';
        _update('Instalando dependencias de CPU');
        await _run(python,['-m','pip','install','torch','torchvision','torchaudio','--index-url','https://download.pytorch.org/whl/cpu'],build.path);
        await _run(python,['-m','pip','install','-r','${build.path}/source/requirements.txt'],build.path);
        await _run(python,['${build.path}/source/main.py','--help'],build.path);
      }else{
        if(release.url==null||release.sha256==null)throw const FormatException('Falta el archivo verificado del motor.');
        _update('Descargando motor verificado');final archive=File('${build.path}/engine.tar.zst');
        _transfer=ResumableTransfer();await _transfer!.fetch(Uri.parse(release.url!),archive,expectedSize:release.bytes,sha:release.sha256,progress:(n,total){_update('${(n/1048576).toStringAsFixed(0)} MiB / ${total==null?'—':(total/1048576).toStringAsFixed(0)} MiB');});
        if(commandRunner==null){
          final listing=await Process.run('tar',['--zstd','-tvf',archive.path]).timeout(const Duration(minutes:2));
          if(listing.exitCode!=0)throw StateError('Instala zstd para extraer el motor.');
          for(final line in (listing.stdout as String).split('\n').where((s)=>s.isNotEmpty)){
            if(!['-','d','l','h'].contains(line[0]))throw const FormatException('Entrada de archivo no admitida.');
            // GNU tar protects leading / and .. in member names. Reject unsafe link targets too.
            final link=line.contains(' -> ')?line.split(' -> ').last:line.contains(' link to ')?line.split(' link to ').last:null;
            if(link!=null&&(link.startsWith('/')||link.split('/').contains('..')))throw const FormatException('Enlace de archivo no válido.');
          }
        }
        await _run('tar',['--zstd','--extract','--file',archive.path,'--directory',build.path,'--no-same-owner','--no-same-permissions'],build.path);
        await _run('${build.path}/bin/ollama',['--version'],build.path);await archive.delete();
      }
      if(cancelled)throw StateError('Operación cancelada.');
      final active={'directory':build.uri.pathSegments.where((s)=>s.isNotEmpty).last,'version':release.version,'revision':release.revision};
      await _publish(release.kind,{'active':active,if(previous!=null)'previous':previous['active']});build=null;
      _update('Instalación lista');
    }catch(_){_update(cancelled?'Operación cancelada.':'No se completó la instalación. Revisa el registro y los requisitos.');rethrow;}
    finally{_transfer=null;busy=false;if(build!=null&&await build.exists())await build.delete(recursive:true);notifyListeners();}
  }
  Future<void> rollback(EngineKind kind)async{
    if(busy||running(kind))throw StateError('Detén el motor y espera la operación actual.');
    final data=await installation(kind);if(data?['previous'] is! Map)throw StateError('No hay una versión anterior.');
    final prior=Map<String,dynamic>.from(data!['previous'] as Map);
    if(!RegExp(r'^build-[a-zA-Z0-9_-]+$').hasMatch(prior['directory'] as String))throw const FormatException('Instalación no válida.');
    if(!await Directory('${(await _folder(kind)).path}/${prior['directory']}').exists())throw StateError('La versión anterior ya no existe.');
    await _publish(kind,{'active':prior,'previous':data['active']});_update('Versión anterior recuperada');
  }
  Future<void> start(EngineKind kind)async{
    if(!AppSettings.instance.get<bool>('allowNetwork'))throw StateError('Acceso a red desactivado.');
    if(!canManage||busy||running(kind))throw StateError('El motor no está disponible para iniciar.');
    final data=await installation(kind);if(data==null)throw StateError('Primero instala el motor.');
    if(!await File(_launcher).exists())throw StateError('Reinstala el paquete Debian para administrar procesos.');
    final active='${(await _folder(kind)).path}/${(data['active'] as Map)['directory']}';
    final socket=await ServerSocket.bind(InternetAddress.loopbackIPv4,0);final port=socket.port;await socket.close();
    final address='http://127.0.0.1:$port';
    final models=await Directory('${(await _folder(kind)).path}/models').create(recursive:true);
    final executable=kind==EngineKind.ollama?'$active/bin/ollama':'$active/venv/bin/python';
    final args=kind==EngineKind.ollama?['serve']:['$active/source/main.py','--cpu','--listen','127.0.0.1','--port','$port','--disable-auto-launch','--base-directory',models.path];
    final p=await Process.start(_launcher,[executable,...args],workingDirectory:active,environment:{'OLLAMA_HOST':'127.0.0.1:$port','OLLAMA_MODELS':models.path,'PYTHONNOUSERSITE':'1'});
    _running[kind]=p;_addresses[kind]=address;
    unawaited(p.stdout.drain<void>());unawaited(p.stderr.drain<void>());
    unawaited(p.exitCode.then((code){if(identical(_running[kind],p)){_running.remove(kind);_update('Motor detenido');}}));
    try{
      final deadline=DateTime.now().add(const Duration(minutes:3));
      while(DateTime.now().isBefore(deadline)){
        if(!identical(_running[kind],p))throw StateError('El motor no pudo iniciar. Revisa su instalación.');
        final http=EngineHttp(address);
        try{await http.json('GET',kind==EngineKind.ollama?'/api/tags':'/system_stats').timeout(const Duration(seconds:3));_update('Motor listo');return;}catch(_){await Future<void>.delayed(const Duration(milliseconds:500));}finally{http.close();}
      }
      throw TimeoutException('El motor no inició a tiempo.');
    }catch(_){await stop(kind);rethrow;}
  }
  static Future<void> _terminate(Process p)async{
    if(!Process.killPid(-p.pid,ProcessSignal.sigterm))p.kill();
    try{await p.exitCode.timeout(const Duration(seconds:3));}catch(_){Process.killPid(-p.pid,ProcessSignal.sigkill);p.kill(ProcessSignal.sigkill);await p.exitCode;}
  }
  Future<void> stop(EngineKind kind)async{final p=_running.remove(kind);if(p!=null)await _terminate(p);_update('Motor detenido');}
  Future<void> cancelInstall()async{cancelled=true;_transfer?.stop();for(final c in _clients){c.close(force:true);}final p=_command;if(p!=null)await _terminate(p);}
  Future<void> stopAll()async{await cancelInstall();for(final k in _running.keys.toList()){await stop(k);}}
}
