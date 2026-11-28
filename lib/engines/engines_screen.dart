import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../localization/strings.dart';
import '../settings/app_settings.dart';
import '../runtime/model_runtime.dart';
import '../media/engine_http.dart';
import 'engine_manager.dart';

class EnginesScreen extends StatefulWidget {
  const EnginesScreen({super.key,required this.runtime});
  final ModelRuntime runtime;
  @override State<EnginesScreen> createState()=>_EnginesScreenState();
}
class _EnginesScreenState extends State<EnginesScreen> {
  final manager=EngineManager.instance;
  final settings=AppSettings.instance;
  late final TextEditingController _ollama,_comfy,_voice;
  final _installed=<EngineKind,Map<String,dynamic>?>{};
  bool _working=false;
  String _status='';
  @override void initState(){super.initState();_ollama=TextEditingController(text:widget.runtime.address.isEmpty?'http://127.0.0.1:11434':widget.runtime.address);_comfy=TextEditingController(text:settings.get<String>('comfyAddress'));_voice=TextEditingController(text:settings.get<String>('voiceAddress'));_refresh();}
  @override void dispose(){_ollama.dispose();_comfy.dispose();_voice.dispose();super.dispose();}
  Future<void> _refresh()async{for(final k in EngineKind.values){_installed[k]=await manager.installation(k);}if(mounted)setState((){});}
  Future<void> _run(Future<void> Function() action)async{
    if(_working)return;setState((){_working=true;_status='';});
    try{await action();if(mounted)setState(()=>_status='Guardado');}
    catch(e){if(mounted)setState(()=>_status=e is SocketException?'No se pudo conectar. Comprueba que el motor esté iniciado y que la dirección sea correcta.':e.toString());}
    finally{if(mounted){setState(()=>_working=false);await _refresh();}}
  }
  Future<void> _install(EngineKind kind)async{
    await _run(()async{
      final release=await manager.latest(kind);if(!mounted)return;
      final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('${S.t('Instalar o actualizar')} ${kind==EngineKind.ollama?'Ollama':'ComfyUI'} ${release.version}'),
        content:Text(S.t('Se instalará en una carpeta de ZASKIA sin permisos de administrador. Se descargarán el motor y sus dependencias; puede ocupar varios GiB. Los modelos se descargan aparte. La instalación anterior se conserva.')),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(S.t('Cancelar'))),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(S.t('Instalar')))]));
      if(accepted==true)await manager.install(release);
    });
  }
  Future<void> _check(String kind)async{
    final address=kind=='ollama'?_ollama.text:kind=='comfy'?_comfy.text:_voice.text;
    final http=EngineHttp(address,allowed:settings.get<bool>('allowNetwork'));
    try{
      await http.json('GET',kind=='ollama'?'/api/tags':kind=='comfy'?'/system_stats':'/v1/models');
      if(kind=='ollama'){widget.runtime.configure(address);await widget.runtime.save();}
      else{await settings.set(kind=='comfy'?'comfyAddress':'voiceAddress',address.trim());}
    }finally{http.close();}
  }
  Future<void> _start(EngineKind k)async=>_run(()async{
    await manager.start(k);final address=manager.address(k);
    if(k==EngineKind.ollama){_ollama.text=address;widget.runtime.configure(address);await widget.runtime.save();}
    else{_comfy.text=address;await settings.set('comfyAddress',address);}
  });
  Future<void> _copyModel(EngineKind k)async{
    await _run(()async{
      final picked=await FilePicker.platform.pickFiles();final path=picked?.files.single.path;if(path==null||!mounted)return;
      final selected=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:Text(S.t('Tipo de componente')),children:[
        for(final entry in {'checkpoints':'Checkpoint','diffusion_models':'Modelo de difusión','text_encoders':'Codificador de texto','vae':'VAE','loras':'LoRA','audio_encoders':'Codificador de audio'}.entries)
          SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,entry.key),child:Text(S.t(entry.value)))]));
      if(selected==null)return;
      final ext=path.split('.').last.toLowerCase();if(!['safetensors','gguf','pt','pth','bin','onnx'].contains(ext))throw const FormatException('Elige un archivo de pesos compatible.');
      final root=await manager.root();final target=await Directory('${root.path}/${k.name}/models/models/$selected').create(recursive:true);
      final file=File('${target.path}/${File(path).uri.pathSegments.last}');if(await file.exists())throw StateError('Ya existe un componente con ese nombre.');
      final partial=File('${file.path}.part');try{await File(path).copy(partial.path);await partial.rename(file.path);}catch(_){if(await partial.exists())await partial.delete();rethrow;}
    });
  }
  Widget _endpoint(String label,TextEditingController c,String kind)=>Column(children:[
    TextField(controller:c,enabled:!_working,decoration:InputDecoration(labelText:S.t(label),border:const OutlineInputBorder())),
    TextButton(onPressed:_working?null:()=>_run(()=>_check(kind)),child:Text(S.t('Comprobar y guardar conexión'))),
  ]);
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:manager,builder:(context,_)=>PopScope(canPop:!_working,child:Scaffold(appBar:AppBar(title:Text(S.t('Gestor de motores'))),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:850),child:ListView(padding:const EdgeInsets.all(24),children:[
    Text(S.t('El motor de texto integrado se actualiza con ZASKIA. Los motores administrados se instalan por separado y no incluyen modelos.')),
    if(!manager.canManage)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(S.t('En Android puedes usar texto local o conectar motores de tu PC. Su instalación y arranque se administran desde Linux. 127.0.0.1 apunta a la propia tablet.'))),
    if(manager.canManage)Text(S.t('Requisitos para instalar: git, python3-venv, zstd y conexión a Internet. ComfyUI administrado utiliza CPU.')),
    if(_working||manager.busy)const LinearProgressIndicator(),
    SelectableText(S.t(_status)),if(manager.status.isNotEmpty)Text(S.t(manager.status)),
    for(final k in EngineKind.values)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(k==EngineKind.ollama?'Ollama':'ComfyUI',style:Theme.of(context).textTheme.titleLarge),
      Text(manager.running(k)?S.t('Ejecutándose en este equipo'):_installed[k]==null?S.t('No instalado por ZASKIA'):'${S.t('Versión instalada')}: ${_installed[k]!['active']['version']}'),
      if(manager.canManage)Wrap(spacing:8,children:[
        OutlinedButton(onPressed:_working||manager.busy||manager.running(k)?null:()=>_install(k),child:Text(S.t('Instalar o actualizar'))),
        FilledButton(onPressed:_working||manager.busy||manager.running(k)||_installed[k]==null?null:()=>_start(k),child:Text(S.t('Iniciar'))),
        TextButton(onPressed:!manager.running(k)?null:()=>manager.stop(k),child:Text(S.t('Detener'))),
        if(_installed[k]?['previous']!=null)TextButton(onPressed:_working||manager.busy||manager.running(k)?null:()=>_run(()=>manager.rollback(k)),child:Text(S.t('Volver a la versión anterior'))),
        if(k==EngineKind.comfy&&_installed[k]!=null)TextButton(onPressed:_working?null:()=>_copyModel(k),child:Text(S.t('Instalar componente de modelo'))),
      ]),
      _endpoint(k==EngineKind.ollama?'Dirección de Ollama':'Dirección de ComfyUI',k==EngineKind.ollama?_ollama:_comfy,k.name),
    ]))),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(S.t('Voz y transcripción')),Text(S.t('Conecta un servidor LocalAI compatible ya instalado. La instalación administrada de voz aún no está disponible.')),_endpoint('Dirección de LocalAI / voz compatible',_voice,'voice')]))),
    if(manager.busy)TextButton(onPressed:manager.cancelInstall,child:Text(S.t('Cancelar instalación'))),
    if(manager.log.isNotEmpty)ExpansionTile(title:Text(S.t('Registro de instalación')),children:[SelectableText(manager.log)]),
  ]))))));
}
