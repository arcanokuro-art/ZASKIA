import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../hardware/hardware_snapshot.dart';
import '../hardware/hardware_advisor.dart';
import '../settings/app_settings.dart';
import '../localization/strings.dart';
import '../runtime/model_runtime.dart';
import '../runtime/model_info.dart';
import '../runtime/model_compatibility.dart';
import '../runtime/downloaded_models.dart';
import '../storage/download_manager.dart';
import '../engines/engines_screen.dart';
import 'starter_catalog.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key,required this.onFinished,this.probe});
  final Future<void> Function() onFinished;
  final Future<HardwareSnapshot> Function()? probe;
  @override State<OnboardingScreen> createState()=>_OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  HardwareSnapshot? _hardware;
  StarterModel _chosen=StarterCatalog.models.first;
  final _runtime=ModelRuntime();
  final downloads=DownloadManager.instance;
  ModelDownload? _task;
  List<File> _existing=[];
  bool _busy=false;
  int _step=0;
  String _status='',_answer='';
  @override void initState(){super.initState();_inspect();}
  @override void dispose(){_runtime.stop();super.dispose();}
  Future<void> _inspect()async{
    try{final h=await (widget.probe??HardwareProbe.read)();var existing=<File>[];try{existing=await DownloadedModels().list();}catch(_){}if(mounted)setState((){_hardware=h;_chosen=StarterCatalog.suggest(h);_existing=existing;});}
    catch(_){if(mounted)setState(()=>_status='No se pudo detectar el equipo. Puedes continuar manualmente.');}
  }
  Future<void> _run(Future<void> Function() action)async{
    if(_busy)return;setState((){_busy=true;_status='';});
    try{await action();}catch(e){if(mounted)setState(()=>_status=e is SocketException?'No se pudo conectar. Comprueba la conexión e inténtalo de nuevo.':e.toString());}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _download()async=>_run(()async{
    final detail=await StarterCatalog.resolve(_chosen,allowNetwork:AppSettings.instance.get<bool>('allowNetwork'));
    if(!mounted)return;
    final metadata=Map<String,dynamic>.from(detail['metadata'] as Map);final bytes=(metadata['size'] as num? ?? (metadata['lfs'] as Map?)?['size'] as num?)?.toInt();
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(S.t('Confirmar descarga')),content:Text('${_chosen.name}\n${S.t('Tamaño')}: ${ModelCompatibility.bytes(bytes)}\n${S.t('Licencia')}: ${detail['license']}\n\n${S.t('Es un modelo de texto pequeño para comenzar. La calidad y la velocidad dependen del modelo y de tu equipo.')}'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(S.t('Cancelar'))),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(S.t('Descargar')))]));
    if(accepted!=true)return;
    await downloads.enqueue(_chosen.repo,detail['revision'] as String,metadata);
    if(mounted)setState((){_task=downloads.tasks.lastWhere((t)=>t.repo==_chosen.repo&&t.name==_chosen.filename);_step=2;});
  });
  Future<void> _load(String path)async{
    final h=_hardware??await HardwareProbe.read();final info=await ModelInfo.inspect(File(path));
    final compatibility=ModelCompatibility.assess(info,h,context:AppSettings.instance.get<int>('context'));
    if(compatibility.blocked)throw StateError(S.t(compatibility.reason));
    if(compatibility.state=='warning'){
      if(!mounted)return;
      final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(S.t('Revisar memoria antes de cargar')),content:Text(S.t(compatibility.reason)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(S.t('Cancelar'))),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(S.t('Intentar cargar')))]));
      if(accepted!=true)return;
    }
    await _runtime.selectLocal(path);if(mounted)setState((){_step=3;_status='Modelo listo para la primera conversación';});
  }
  Future<void> _import()async=>_run(()async{
    final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['gguf']);final path=picked?.files.single.path;if(path==null)return;
    final file=await DownloadedModels().import(path);await _load(file.path);
  });
  Future<void> _test()async=>_run(()async{
    setState(()=>_answer='');
    await for(final packet in _runtime.stream('/api/chat',{'model':_runtime.model,'messages':[{'role':'user','content':'Responde en español con un saludo breve.'}],'options':{'num_predict':32,'temperature':0.2}})){
      if(!mounted)break;setState(()=>_answer+=packet['message']?['content'] as String? ?? '');
    }
    if(mounted)setState(()=>_status=_answer.isEmpty?'El modelo terminó sin texto. Revisa su compatibilidad.':'Primera respuesta recibida');
  });
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:downloads,builder:(context,_)=>PopScope(canPop:!_busy,child:Scaffold(appBar:AppBar(title:Text(S.t('Comenzar con ZASKIA')),actions:[TextButton(onPressed:_busy?null:()=>_run(widget.onFinished),child:Text(S.t('Configurar después')))]),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:800),child:ListView(padding:const EdgeInsets.all(24),children:[
    Text(S.t('Tu primera IA, paso a paso'),style:Theme.of(context).textTheme.headlineSmall),
    Text(S.t('Elegirás el modelo antes de descargar. No se instala ningún peso automáticamente.')),
    const SizedBox(height:20),Wrap(spacing:8,children:[for(var i=0;i<4;i++)ChoiceChip(label:Text('${i+1}. ${S.t(['Equipo','Modelo','Preparación','Primera respuesta'][i])}'),selected:_step==i,onSelected:_busy||i>_step?null:(_)=>setState(()=>_step=i))]),
    if(_busy)const LinearProgressIndicator(),
    if(_step==0)...[
      const SizedBox(height:20),Text(_hardware==null?S.t('Detectando equipo…'):'${_hardware!.os} · ${_hardware!.architecture} · ${_hardware!.usableCores} ${S.t('núcleos disponibles')}'),
      if(_hardware!=null)...[Text('${S.t('RAM total')}: ${ModelCompatibility.bytes(_hardware!.totalMemory)}\n${S.t('RAM disponible')}: ${ModelCompatibility.bytes(_hardware!.availableMemory)}'),Text(S.t('La memoria disponible es una medición del momento, no una garantía de carga.')),
        if(_hardware!.nativeSupported)FilledButton(onPressed:_busy?null:()=>_run(()async{await AppSettings.instance.update(HardwareAdvisor.recommend(_hardware!).settings);if(mounted)setState(()=>_step=1);}),child:Text(S.t('Usar configuración recomendada')))
        else Text(S.t('El motor integrado no admite este equipo. Puedes conectar un motor externo.')),
      ],
      OutlinedButton(onPressed:_busy?null:()=>setState(()=>_step=1),child:Text(S.t('Continuar sin cambiar ajustes'))),
    ],
    if(_step==1)...[
      if(_existing.isNotEmpty)Text(S.t('Modelos ya disponibles')),
      for(final file in _existing)ListTile(title:Text(file.uri.pathSegments.last),trailing:TextButton(onPressed:_busy?null:()=>_run(()=>_load(file.path)),child:Text(S.t('Cargar')))),
      for(final model in StarterCatalog.models)RadioListTile<StarterModel>(value:model,groupValue:_chosen,onChanged:_busy?null:(m)=>setState(()=>_chosen=m!),title:Text(model.name),subtitle:Text('${S.t('Descarga aproximada')}: ${ModelCompatibility.bytes(model.approximateBytes)}')),
      Text(S.t('La sugerencia usa la memoria observada. Comprueba el tamaño real y la licencia antes de descargar.')),
      FilledButton(onPressed:_busy||_hardware?.nativeSupported!=true?null:_download,child:Text(S.t('Revisar y descargar modelo'))),
      OutlinedButton(onPressed:_busy||_hardware?.nativeSupported!=true?null:_import,child:Text(S.t('Ya tengo un GGUF'))),
      TextButton(onPressed:_busy?null:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>EnginesScreen(runtime:_runtime))),child:Text(S.t('Usar o instalar otro motor'))),
    ],
    if(_step==2)...[
      if(_task!=null)...[Text(_task!.name),Text(S.t(_task!.status)),LinearProgressIndicator(value:_task!.progress),if(_task!.error.isNotEmpty)SelectableText(_task!.error),
        Wrap(spacing:8,children:[if(!_task!.finished&&!_task!.paused)TextButton(onPressed:()=>downloads.pause(_task!),child:Text(S.t('Pausar'))),if(_task!.paused||_task!.status=='Error')TextButton(onPressed:_task!.running?null:()=>downloads.resume(_task!),child:Text(S.t('Reanudar')))]),
        FilledButton(onPressed:_busy||_task!.status!='Guardado'?null:()=>_run(()=>_load(_task!.destination)),child:Text(S.t('Cargar y preparar chat'))),
      ],
    ],
    if(_step==3)...[
      Text(_runtime.selectedName),Text(S.t('Modelo listo para la primera conversación')),
      FilledButton(onPressed:_busy?null:_test,child:Text(S.t('Probar saludo'))),if(_busy)TextButton(onPressed:_runtime.stop,child:Text(S.t('Detener'))),
      if(_answer.isNotEmpty)Padding(padding:const EdgeInsets.all(16),child:SelectableText(_answer)),
      OutlinedButton(onPressed:_busy?null:()=>_run(widget.onFinished),child:Text(S.t('Ir al chat'))),
    ],
    if(_status.isNotEmpty)Padding(padding:const EdgeInsets.only(top:16),child:SelectableText(S.t(_status))),
  ]))))));
}
