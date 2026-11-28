import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import '../localization/strings.dart';
import '../settings/app_settings.dart';
import 'engine_http.dart';
import 'comfy_engine.dart';
import 'voice_engine.dart';
import 'media_store.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key,this.initialPrompt='',this.initialImage});
  final String initialPrompt;
  final String? initialImage;
  @override
  State<MediaScreen> createState()=>_MediaScreenState();
}
class _MediaScreenState extends State<MediaScreen> with WidgetsBindingObserver {
  final s=AppSettings.instance, _store=MediaStore();
  final _prompt=TextEditingController(),_negative=TextEditingController(),_seed=TextEditingController(text:'-1');
  late final TextEditingController _comfy,_voice,_speechModel,_transcriptModel,_voiceName;
  String _kind='image',_status='',_checkpoint='',_transcription='';
  List<String> _checkpoints=[];
  Map<String,dynamic>? _workflow;
  String? _input;
  bool _busy=false;
  int _width=512,_height=512,_steps=20;
  double _cfg=7,_denoise=0.7;
  EngineHttp? _http;
  ComfyEngine? _engine;
  List<Map<String,dynamic>> _jobs=[];
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);
    _comfy=TextEditingController(text:s.get<String>('comfyAddress'));_voice=TextEditingController(text:s.get<String>('voiceAddress'));
    _speechModel=TextEditingController(text:s.get<String>('speechModel'));_transcriptModel=TextEditingController(text:s.get<String>('transcriptionModel'));_voiceName=TextEditingController(text:s.get<String>('voiceName'));
    _prompt.text=widget.initialPrompt;_input=widget.initialImage;_refresh();
  }
  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);_http?.cancel();for(final c in [_prompt,_negative,_seed,_comfy,_voice,_speechModel,_transcriptModel,_voiceName]){c.dispose();}super.dispose();}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if((state==AppLifecycleState.paused||state==AppLifecycleState.hidden)&&!s.get<bool>('backgroundWork')){unawaited(_cancel());}}
  Future<void> _refresh()async{final jobs=await _store.list();if(mounted)setState(()=>_jobs=jobs);}
  Future<void> _saveSettings()async{
    EngineHttp.validateAddress(_comfy.text);EngineHttp.validateAddress(_voice.text);
    await s.update({'comfyAddress':_comfy.text.trim(),'voiceAddress':_voice.text.trim(),'speechModel':_speechModel.text.trim(),'transcriptionModel':_transcriptModel.text.trim(),'voiceName':_voiceName.text.trim()});
  }
  EngineHttp _connect(String address){final h=EngineHttp(address,allowed:s.get<bool>('allowNetwork'));_http=h;return h;}
  Future<void> _check()async{
    if(_busy)return;setState(()=>_busy=true);
    try{await _saveSettings();
      if(_kind=='voice'){
        final models=await VoiceEngine(_connect(_voice.text)).models();if(mounted)setState(()=>_status='${S.t('Modelos disponibles')}: ${models.join(', ')}');
      }else{
        final engine=ComfyEngine(_connect(_comfy.text));final nodes=await engine.capabilities();
        final checkpoints=await engine.checkpoints();if(mounted)setState((){_checkpoints=checkpoints;_checkpoint=checkpoints.contains(_checkpoint)?_checkpoint:checkpoints.firstOrNull??'';_status='${nodes.length} ${S.t('nodos disponibles')}';});
      }
    }catch(e){if(mounted)setState(()=>_status=e.toString());}finally{_http?.close();_http=null;if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _importWorkflow()async{
    final file=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);final path=file?.files.single.path;if(path==null)return;
    try{if(await File(path).length()>4*1024*1024)throw const FormatException('Flujo demasiado grande.');final w=ComfyEngine.parseWorkflow(await File(path).readAsString());if(mounted)setState((){_workflow=w;_status='Flujo API importado';});}
    catch(e){if(mounted)setState(()=>_status=e.toString());}
  }
  Future<void> _pickInput()async{
    final p=await FilePicker.platform.pickFiles(type:_kind=='voice'?FileType.audio:FileType.image);if(p?.files.single.path!=null&&mounted)setState(()=>_input=p!.files.single.path);
  }
  Future<void> _cancel()async{
    if(!_busy)return;
    try{if(_engine!=null){await _engine!.cancel();}else{_http?.cancel();}}
    catch(_){_http?.cancel();if(mounted)setState(()=>_status='Cancelación local; comprueba la cola del motor.');}
  }
  Future<void> _generate({bool transcribe=false})async{
    if(_busy)return;
    setState((){_busy=true;_status='Procesando en el motor';_transcription='';});
    Directory? job;
    try{
      await _saveSettings();
      if(!transcribe && _prompt.text.trim().isEmpty)throw const FormatException('Escribe una descripción.');
      job=await _store.create(_kind,_prompt.text);
      final files=<File>[];
      final metadata=await _store.read(job);
      if(_kind=='voice'){
        final voice=VoiceEngine(_connect(_voice.text));
        if(transcribe){if(_input==null)throw const FormatException('Selecciona un archivo de audio.');
          final text=await voice.transcribe(File(_input!),_transcriptModel.text);files.add(await File('${job.path}/transcription.txt').writeAsString(text));
          if(mounted)setState(()=>_transcription=text);
        }else{files.add(await voice.speak(_prompt.text,_speechModel.text,_voiceName.text,File('${job.path}/speech.wav')));}
        metadata['model']=transcribe?_transcriptModel.text:_speechModel.text;
      }else{
        final engine=ComfyEngine(_connect(_comfy.text));_engine=engine;
        var seed=int.tryParse(_seed.text)??-1;if(seed<0)seed=Random.secure().nextInt(1<<32);
        String? input;
        if(_input!=null)input=await engine.upload(File(_input!));
        Map<String,dynamic> workflow;
        if(_workflow!=null){
          if(jsonEncode(_workflow).contains('{{input_image}}') && input==null)throw const FormatException('El flujo requiere una imagen de entrada.');
          workflow=Map<String,dynamic>.from(ComfyEngine.substitute(_workflow,{'prompt':_prompt.text,'negative_prompt':_negative.text,'seed':seed,'width':_width,'height':_height,'steps':_steps,'cfg':_cfg,'input_image':input??''}) as Map);
        }else{
          if(_kind!='image')throw const FormatException('Importa un flujo API para esta modalidad.');
          if(_checkpoint.isEmpty)throw const FormatException('Comprueba la conexión y elige un checkpoint.');
          workflow=ComfyEngine.imageWorkflow(checkpoint:_checkpoint,prompt:_prompt.text,negative:_negative.text,seed:seed,width:_width,height:_height,steps:_steps,cfg:_cfg,image:input,denoise:_denoise);
        }
        await File('${job.path}/workflow.json').writeAsString(jsonEncode(workflow));
        metadata['seed']=seed;metadata['checkpoint']=_checkpoint;
        files.addAll(await engine.generate(workflow,job,status:(v){if(mounted)setState(()=>_status=v);}));
      }
      await _store.record(job,{...metadata,'status':'Guardado','files':files.map((f)=>f.uri.pathSegments.last).toList()});
      if(mounted)setState(()=>_status='Guardado');
    }catch(e){if(job!=null){final data=await _store.read(job);await _store.record(job,{...data,'status':'Error o cancelación','error':e.toString()});}if(mounted)setState(()=>_status=e.toString());}
    finally{_http?.close();_http=null;_engine=null;if(mounted){setState(()=>_busy=false);await _refresh();}}
  }
  Future<void> _export(Map<String,dynamic> job)async{
    final folder=await FilePicker.platform.getDirectoryPath();if(folder==null)return;
    try{final source=Directory(job['directory'] as String);final target=await Directory(folder).createTemp('ZASKIA-media-');
      await for(final e in source.list()){if(e is File&&!e.path.endsWith('.part'))await e.copy('${target.path}/${e.uri.pathSegments.last}');}
      if(mounted)setState(()=>_status='${S.t('Guardado')}: ${target.path}');
    }catch(e){if(mounted)setState(()=>_status=e.toString());}
  }
  Widget _field(TextEditingController c,String label,{int lines=1})=>Padding(padding:const EdgeInsets.symmetric(vertical:8),child:TextField(controller:c,enabled:!_busy,maxLines:lines,decoration:InputDecoration(labelText:S.t(label),border:const OutlineInputBorder())));
  Widget _dimension(String label,int value,ValueChanged<int> onChanged)=>DropdownButtonFormField<int>(value:value,decoration:InputDecoration(labelText:S.t(label)),items:[for(final n in [256,512,768,1024])DropdownMenuItem(value:n,child:Text('$n'))],onChanged:_busy?null:(v)=>onChanged(v!));
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!_busy,child:Scaffold(appBar:AppBar(title:Text(S.t('Estudio multimedia'))),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:ListView(padding:const EdgeInsets.all(24),children:[
    Text(S.t('Los motores se ejecutan por separado en este equipo o en tu red. Instala sus modelos allí. En Android, 127.0.0.1 es la propia tablet; usa la IP de tu PC para conectarte a ella.')),
    const SizedBox(height:16),DropdownButtonFormField<String>(value:_kind,isExpanded:true,decoration:InputDecoration(labelText:S.t('Modalidad')),items:[for(final e in {'image':'Imagen','voice':'Voz','music':'Música','video':'Video'}.entries)DropdownMenuItem(value:e.key,child:Text(S.t(e.value)))],onChanged:_busy?null:(v)=>setState((){_kind=v!;_workflow=null;_input=null;_status='';})),
    _field(_kind=='voice'?_voice:_comfy,_kind=='voice'?'Dirección de LocalAI / voz compatible':'Dirección de ComfyUI'),
    OutlinedButton(onPressed:_busy?null:_check,child:Text(S.t('Comprobar conexión'))),
    if(_kind=='voice')...[_field(_speechModel,'Modelo de síntesis de voz'),_field(_voiceName,'Nombre de voz'),_field(_transcriptModel,'Modelo de transcripción')]
    else ...[
      if(_kind=='image'&&_checkpoints.isNotEmpty)DropdownButtonFormField<String>(value:_checkpoint,decoration:InputDecoration(labelText:S.t('Checkpoint de imagen')),isExpanded:true,items:[for(final c in _checkpoints)DropdownMenuItem(value:c,child:Text(c,overflow:TextOverflow.ellipsis))],onChanged:_busy?null:(v)=>setState(()=>_checkpoint=v!)),
      Text(S.t('Imagen básica: checkpoint compatible con CLIP y VAE. Para FLUX, Qwen, música o video, importa un flujo API con sus nodos y modelos instalados.')),
      Wrap(spacing:8,children:[OutlinedButton(onPressed:_busy?null:_importWorkflow,child:Text(S.t('Importar flujo API'))),if(_workflow!=null)TextButton(onPressed:_busy?null:()=>setState(()=>_workflow=null),child:Text(S.t('Quitar flujo')))]),
      if(_workflow!=null)Text('${_workflow!.length} ${S.t('nodos del flujo')}'),
      Text(S.t('Variables del flujo: {{prompt}}, {{negative_prompt}}, {{seed}}, {{width}}, {{height}}, {{steps}}, {{cfg}}, {{input_image}}.')),
    ],
    _field(_prompt,_kind=='voice'?'Texto para voz':'Descripción',lines:4),
    if(_kind!='voice')...[_field(_negative,'Descripción negativa'),_field(_seed,'Semilla (-1 aleatoria)'),Row(children:[Expanded(child:_dimension('Ancho',_width,(v)=>setState(()=>_width=v))),const SizedBox(width:16),Expanded(child:_dimension('Alto',_height,(v)=>setState(()=>_height=v)))]),
      Text('${S.t('Pasos')}: $_steps'),Slider(value:_steps.toDouble(),min:1,max:60,divisions:59,onChanged:_busy?null:(v)=>setState(()=>_steps=v.round())),
      Text('CFG: $_cfg'),Slider(value:_cfg,min:1,max:20,divisions:38,onChanged:_busy?null:(v)=>setState(()=>_cfg=v)),
      if(_input!=null)...[Text('${S.t('Intensidad de edición')}: $_denoise'),Slider(value:_denoise,min:0,max:1,divisions:20,onChanged:_busy?null:(v)=>setState(()=>_denoise=v))],
    ],
    Wrap(spacing:8,children:[TextButton.icon(onPressed:_busy?null:_pickInput,icon:const Icon(Icons.attach_file),label:Text(S.t(_kind=='voice'?'Seleccionar audio':'Seleccionar imagen de entrada'))),if(_input!=null)TextButton(onPressed:_busy?null:()=>setState(()=>_input=null),child:Text(S.t('Quitar')))]),
    if(_input!=null)Text(File(_input!).uri.pathSegments.last),
    Wrap(spacing:8,children:[FilledButton(onPressed:_busy?null:()=>_generate(),child:Text(S.t('Generar'))),if(_kind=='voice')OutlinedButton(onPressed:_busy||_input==null?null:()=>_generate(transcribe:true),child:Text(S.t('Transcribir audio'))),if(_busy)TextButton(onPressed:_cancel,child:Text(S.t('Cancelar')))]),
    if(_busy)const LinearProgressIndicator(),SelectableText(S.t(_status)),
    if(_transcription.isNotEmpty)...[SelectableText(_transcription),TextButton(onPressed:()=>Clipboard.setData(ClipboardData(text:_transcription)),child:Text(S.t('Copiar')))],
    const Divider(height:32),Text(S.t('Galería local'),style:Theme.of(context).textTheme.titleLarge),
    for(final job in _jobs)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('${S.t({'image':'Imagen','voice':'Voz','music':'Música','video':'Video'}[job['kind']]??'Archivo')} · ${S.t(job['status']=='Procesando en el motor'&&!_busy?'Interrumpida':job['status'] as String)}'),Text(job['prompt'] as String),
      if(job['error']!=null)Text(job['error'] as String),
      for(final name in (job['files'] as List? ?? []).cast<String>())Builder(builder:(context){final f=File('${job['directory']}/$name');return Column(children:[
        if(RegExp(r'\.(png|jpg|jpeg|webp)$').hasMatch(name))Image.file(f,height:240,fit:BoxFit.contain,errorBuilder:(_,e,st)=>Text(S.t('No se pudo abrir el archivo.'))),
        ListTile(title:Text(name),trailing:IconButton(tooltip:S.t('Abrir archivo'),icon:const Icon(Icons.open_in_new),onPressed:()async{final result=await OpenFilex.open(f.path);if(mounted&&result.type!=ResultType.done)setState(()=>_status=result.message);})),
      ]);}),
      Wrap(spacing:8,children:[TextButton(onPressed:()=>_export(job),child:Text(S.t('Exportar archivos'))),TextButton(onPressed:_busy?null:()async{final d=Directory(job['directory'] as String);final data=await _store.read(d);if(mounted)setState((){_prompt.text=data['prompt'] as String;if(data['seed']!=null)_seed.text='${data['seed']}';});final f=File('${d.path}/workflow.json');if(await f.exists()){final workflow=ComfyEngine.parseWorkflow(await f.readAsString());if(mounted)setState(()=>_workflow=workflow);}},child:Text(S.t('Reutilizar')))]),
    ]))),
  ])))));
}
