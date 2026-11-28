import '../media/media_screen.dart';
import '../storage/downloads_screen.dart';
import '../execution/execution_screen.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../localization/strings.dart';
import '../storage/model_storage.dart';
import '../storage/download_manager.dart';
import '../storage/backup_service.dart';
import '../diagnostics/device_info.dart';
import '../diagnostics/diagnostic_log.dart';
import '../updates/update_service.dart';
import '../runtime/model_runtime.dart';
import '../runtime/models_screen.dart';
import '../workspace/project_store.dart';
import 'app_settings.dart';
import '../hardware/hardware_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key,required this.runtime});
  final ModelRuntime runtime;
  @override
  State<SettingsScreen> createState()=>_SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  final s=AppSettings.instance;
  String _query='', _status='';
  bool _advanced=false,_working=false;
  Map<String,String> _device={};
  String _storage='';
  Map<String,dynamic>? _update;
  @override
  void initState(){super.initState();_refresh();}
  Future<void> _refresh() async {
    try {
    final device=await DeviceInfo.read();
    var bytes=0;
    for(final root in await ModelStorage.roots()){bytes+=await ModelStorage.size(root);}
    final folder=await ModelStorage.root();
    if(mounted)setState((){_device=device;_storage='${folder.path}\n${(bytes/1073741824).toStringAsFixed(2)} GiB';});
    } catch(e) {await DiagnosticLog.record('storage-info',e);if(mounted)setState(()=>_status='No se pudo completar la operación.');}
  }
  Future<void> _run(Future<void> Function() action) async {
    if(_working)return;
    setState((){_working=true;_status='';});
    try {await action();widget.runtime.refreshRetention();if(mounted)setState(()=>_status='Guardado');}
    catch(e){await DiagnosticLog.record('settings',e);if(mounted)setState(()=>_status='No se pudo completar la operación.');}
    finally{if(mounted)setState(()=>_working=false);}
  }
  Future<bool> _confirm(String title) async=>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
    title:Text(S.t(title)),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('Cancelar'))),
    FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('Continuar')))]))??false;
  Future<void> _folder(String key) async {
    final path=await FilePicker.platform.getDirectoryPath();
    if(path==null)return;
    await _run(()async{
      final probe=await Directory(path).createTemp('.zaskia-check-');await probe.delete();
      if(key=='modelFolder'){
        final previous=s.get<String>('modelFolder');
        final folders=<String>{...s.get<List>('modelFolders').cast<String>(),if(previous.isNotEmpty)previous,path};
        await s.update({'modelFolder':path,'modelFolders':folders.toList()});
      } else {await s.set(key,path);}
      await _refresh();
    });
  }
  Future<void> _edit(String key,String title) async {
    final controller=TextEditingController(text:s.get<String>(key));
    final value=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t(title)),content:SizedBox(width:560,child:TextField(controller:controller,maxLines:8,maxLength:8000)),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('Cancelar'))),
        FilledButton(onPressed:()=>Navigator.pop(c,controller.text),child:Text(S.t('Guardar'))) ]));
    controller.dispose();
    if(value!=null)await _run(()=>s.set(key,value));
  }
  Widget _toggle(String key,String label,{String? help})=>SwitchListTile(
    title:Text(S.t(label)),subtitle:help==null?null:Text(S.t(help)),value:s.get<bool>(key),
    onChanged:_working?null:(v)=>_run(()=>s.set(key,v)));
  Widget _select(String key,String label,Map<dynamic,String> options)=>Padding(
    padding:const EdgeInsets.all(12),child:DropdownButtonFormField<dynamic>(
      value:options.containsKey(s.snapshot[key])?s.snapshot[key]:options.keys.first,
      isExpanded:true,decoration:InputDecoration(labelText:S.t(label),border:const OutlineInputBorder()),
      items:[for(final e in options.entries)DropdownMenuItem(value:e.key,child:Text(S.t(e.value)))],
      onChanged:_working?null:(v)async{
        if(key=='backupHours' && v!=0 && s.get<String>('backupFolder').isEmpty){await _folder('backupFolder');if(s.get<String>('backupFolder').isEmpty)return;}
        await _run(()=>s.set(key,v));
      }));
  Widget _slider(String key,String label,double min,double max,int divisions)=>Column(children:[
    ListTile(title:Text(S.t(label)),trailing:Text('${s.snapshot[key]}')),
    Slider(value:(s.snapshot[key] as num).toDouble().clamp(min,max).toDouble(),min:min,max:max,divisions:divisions,
      onChanged:_working?null:(v)=>_run(()=>s.set(key,['temperature','textScale'].contains(key)?v:v.round()))),
  ]);
  Widget _action(String label,IconData icon,VoidCallback action,{String? subtitle,bool translateSubtitle=true})=>ListTile(
    leading:Icon(icon),title:Text(S.t(label)),subtitle:subtitle==null?null:Text(translateSubtitle?S.t(subtitle):subtitle),
    onTap:_working?null:action);
  Widget _section(String title,List<Widget> children,List<String> keys,{String tags=''}) {
    if(_query.isNotEmpty && !(S.t(title)+' '+tags).toLowerCase().contains(_query.toLowerCase()) &&
      !('$title $tags').toLowerCase().contains(_query.toLowerCase()))return const SizedBox.shrink();
    return Card(margin:const EdgeInsets.only(bottom:20),child:Padding(padding:const EdgeInsets.all(12),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[Expanded(child:Text(S.t(title),style:Theme.of(context).textTheme.titleLarge)),
      if(keys.isNotEmpty)IconButton(tooltip:S.t('Restablecer este apartado'),icon:const Icon(Icons.restart_alt),onPressed:_working?null:()async{
        if(await _confirm('¿Restablecer este apartado?'))await _run(()=>s.reset(keys));
      })]),...children])));
  }
  Future<void> _export()async{
    final folder=await FilePicker.platform.getDirectoryPath();if(folder==null)return;
    await _run(()async{await BackupService.export('$folder/ZASKIA-${DateTime.now().millisecondsSinceEpoch}.zaskia');});
  }
  Future<void> _restore()async{
    final picked=await FilePicker.platform.pickFiles();final path=picked?.files.single.path;if(path==null||!mounted)return;
    var settings=false;
    final confirmed=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('Restaurar respaldo')),content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(S.t('Las conversaciones se añadirán sin borrar las existentes.')),
        CheckboxListTile(value:settings,onChanged:(v)=>set(()=>settings=v??false),title:Text(S.t('Importar ajustes también')))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('Cancelar'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('Restaurar'))) ])));
    if(confirmed!=true)return;
    await _run(()async{await BackupService.restore(path,settings:settings);if(mounted)Navigator.pop(context,true);});
  }
  Future<void> _openUrl(String url)async{
    if(!s.get<bool>('allowNetwork')){setState(()=>_status='Acceso a red desactivado.');return;}
    await _run(()async{if(!await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication))throw StateError('URL');});
  }
  Future<void> _saveProfile()async{
    final c=TextEditingController();
    final name=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(S.t('Nombre del perfil')),
      content:TextField(controller:c,maxLength:60),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(S.t('Cancelar'))),
        FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:Text(S.t('Guardar')))]));
    c.dispose();if(name==null||name.isEmpty)return;
    final values={for(final k in ['threads','context','maxTokens','temperature','systemPrompt','idleMinutes'])k:s.snapshot[k]};
    await _run(()=>s.set('customProfiles',[...s.get<List>('customProfiles'),{'name':name,'values':values}]));
  }
  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:s,builder:(context,_)=>Scaffold(
    appBar:AppBar(title:Text(S.t('Configuración'))),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:ListView(
      padding:const EdgeInsets.all(20),children:[
      TextField(decoration:InputDecoration(prefixIcon:const Icon(Icons.search),labelText:S.t('Buscar ajustes')),
        onChanged:(v)=>setState(()=>_query=v)),
      if(_working)const LinearProgressIndicator(),
      if(_status.isNotEmpty)Padding(padding:const EdgeInsets.all(12),child:Text(S.t(_status))),
      if(s.error!=null)Text(S.t(s.error!)),
      SwitchListTile(title:Text(S.t('Opciones avanzadas')),value:_advanced,onChanged:(v)=>setState(()=>_advanced=v)),
      _section('Idioma',[
        _select('language','Idioma de la interfaz',{'es':'Español','en':'English','zh':'中文（简体）','ko':'한국어','ja':'日本語','fr':'Français'}),
        _select('responseLanguage','Idioma de las respuestas',{'auto':'Según la conversación','es':'Español','en':'English','zh':'中文（简体）','ko':'한국어','ja':'日本語','fr':'Français'}),
      ],['language','responseLanguage']),
      _section('Apariencia',[
        _select('theme','Tema',{'system':'Sistema','light':'Claro','dark':'Oscuro'}),
        _slider('textScale','Tamaño del texto',0.8,1.8,10),_toggle('compact','Barra lateral compacta'),
        _toggle('contrast','Alto contraste'),_toggle('reduceMotion','Reducir animaciones'),
      ],['theme','textScale','compact','contrast','reduceMotion']),
      _section('Perfiles de uso',[
        for(final e in {'balanced':'Equilibrado','economy':'Ahorro','creative':'Escritura creativa','code':'Programación'}.entries)
          ListTile(title:Text(S.t(e.value)),trailing:s.get<String>('profile')==e.key?const Icon(Icons.check):null,
            onTap:_working?null:()=>_run(()=>s.profile(e.key))),
        _action('Guardar perfil actual',Icons.bookmark_add_outlined,_saveProfile),
        for(final raw in s.get<List>('customProfiles'))Builder(builder:(context){final profile=raw as Map;return ListTile(
          title:Text(profile['name'] as String),onTap:_working?null:()=>_run(()=>s.update({...Map<String,dynamic>.from(profile['values'] as Map),'profile':'custom'})),
          trailing:IconButton(icon:const Icon(Icons.delete_outline),tooltip:S.t('Eliminar'),onPressed:_working?null:()=>_run(()=>s.set('customProfiles',s.get<List>('customProfiles').where((v)=>v!=raw).toList()))));}),
      ],['profile','customProfiles']),
      _section('Conversación',[
        _action('Instrucciones predeterminadas',Icons.edit_outlined,()=>_edit('systemPrompt','Instrucciones predeterminadas'),subtitle:s.get<String>('systemPrompt').isEmpty?S.t('Sin instrucciones adicionales'):s.get<String>('systemPrompt'),translateSubtitle:false),
        _toggle('enterSends','Enter para enviar',help:'Shift+Enter inserta una línea. Ctrl+Enter siempre envía.'),
        _slider('maxTokens','Longitud máxima de respuesta',32,8192,255),
        if(_advanced)_slider('temperature','Temperatura',0,2,20),
      ],['systemPrompt','enterSends','maxTokens','temperature'],tags:'temperatura tokens teclado'),
      _section('Rendimiento y energía',[
        Text(S.t('Los cambios de CPU y contexto se aplican al volver a cargar el modelo.')),
        _select('idleMinutes','Liberar modelo tras inactividad',{0:'Nunca',3:'3 min',10:'10 min',30:'30 min',60:'60 min'}),
        _toggle('backgroundWork','Continuar al minimizar',help:'Si se desactiva, minimizar detiene generación y descargas. El sistema puede limitar el trabajo en segundo plano.'),
        _action('Liberar memoria ahora',Icons.memory,()=>_run(widget.runtime.releaseMemory)),
        if(_advanced)...[_slider('threads','Hilos de CPU',1,64,63),_select('context','Tamaño del contexto',{512:'512',1024:'1024',2048:'2048',4096:'4096',8192:'8192',16384:'16384',32768:'32768'}),
          Text(S.t('Un contexto mayor consume más RAM.'))],
      ],['threads','context','idleMinutes','backgroundWork'],tags:'RAM CPU contexto'),
      _section('Modelos y almacenamiento',[
        SelectableText(_storage),
        _action('Elegir carpeta de modelos',Icons.folder_open,()=>_folder('modelFolder'),subtitle:'Afecta nuevas descargas e importaciones. Los modelos anteriores siguen visibles.'),
        _action('Actualizar uso del espacio',Icons.refresh,()=>_run(_refresh)),
        _action('Eliminar descargas incompletas',Icons.cleaning_services_outlined,()async{if(await _confirm('¿Eliminar descargas incompletas?'))await _run(()async{if(DownloadManager.instance.busy)throw StateError('Downloads active');await ModelStorage.clearPartial();await _refresh();});}),
        _select('largeDownloadMB','Confirmar descargas mayores a',{100:'100 MB',500:'500 MB',1000:'1 GB',5000:'5 GB',10000:'10 GB'}),
        _select('maxDownloads','Descargas simultáneas',{1:'1',2:'2',3:'3'}),
        _action('Cancelar todas las descargas',Icons.cancel_outlined,()=>DownloadManager.instance.cancelAll()),
      ],['modelFolder','largeDownloadMB','maxDownloads']),
      _section('Motores y conexiones',[
        _action('Configuración de ejecución',Icons.tune,()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>ExecutionScreen(runtime:widget.runtime)))),
        _action('Estudio multimedia',Icons.auto_awesome_outlined,()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const MediaScreen()))),
        _action('Descargas',Icons.download_outlined,()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const DownloadsScreen()))),
        ListTile(title:Text(S.t('Motor integrado')),subtitle:Text('llama.cpp · CPU · GGUF')),
        _action('Configurar Ollama y modelos',Icons.settings_input_component,()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ModelsScreen(runtime:widget.runtime)))),
        _action('Comprobar conexión Ollama',Icons.network_check,()=>_run(()async{await widget.runtime.models();})),
      ],[]),
      _section('Inicio',[
        _select('startup','Al abrir ZASKIA',{'last':'Recuperar último chat','new':'Comenzar un chat nuevo'}),
        _toggle('autoLoad','Cargar el modelo seleccionado al iniciar'),
      ],['startup','autoLoad']),
      _section('Memoria',[
        _toggle('remember','Usar memoria personal',help:'Solo se incluye lo que escribas aquí. Puedes editarlo o borrarlo.'),
        _action('Ver y editar memoria',Icons.psychology_outlined,()=>_edit('memory','Memoria personal')),
        _action('Borrar memoria',Icons.delete_outline,()async{if(await _confirm('¿Borrar memoria?'))await _run(()=>s.set('memory',''));}),
      ],['remember','memory']),
      _section('Permisos y privacidad',[
        _toggle('allowNetwork','Permitir conexiones de red',help:'Controla Hugging Face, Ollama y búsqueda de actualizaciones.'),
        _toggle('allowAttachments','Permitir archivos en las conversaciones'),
        Text(S.t('No se ejecutan comandos ni agentes. Esos permisos se incorporarán con el motor de agentes.')),
      ],['allowNetwork','allowAttachments']),
      _section('Respaldos y datos',[
        Text(S.t('Copias locales sin cifrar: chats, adjuntos y ajustes. No incluyen modelos. Límite: 32 MB de adjuntos.')),
        _action('Crear respaldo',Icons.save_alt,_export),_action('Restaurar respaldo',Icons.restore,_restore),
        _action('Carpeta de respaldos',Icons.folder,()=>_folder('backupFolder'),subtitle:s.get<String>('backupFolder')),
        _select('backupHours','Respaldos mientras ZASKIA está abierta',{0:'Desactivados',1:'Cada hora',24:'Cada día',168:'Cada semana'}),
        if(s.get<int>('lastBackup')>0)Text(DateTime.fromMillisecondsSinceEpoch(s.get<int>('lastBackup')).toLocal().toString()),
        _action('Borrar todo el historial',Icons.delete_forever,()async{if(await _confirm('¿Borrar todo el historial?'))await _run(()async{
          for(final p in await ProjectStore().list()){await ProjectStore().remove(p.id);}if(mounted)Navigator.pop(context,true);
        });}),
      ],['backupFolder','backupHours','lastBackup']),
      _section('Mi equipo',[
        _action('Hardware y prueba de rendimiento',Icons.speed,()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>HardwareScreen(runtime:widget.runtime)))),
        for(final e in _device.entries)ListTile(title:Text(S.t(e.key)),subtitle:SelectableText(e.value)),
        Text(S.t('Estimación orientativa: empieza con pesos de modelo menores a la mitad de la RAM disponible. El contexto y el motor necesitan memoria adicional.')),
        _action('Actualizar información del equipo',Icons.refresh,()=>_run(_refresh)),
      ],[]),
      _section('Actualizaciones',[
        const ListTile(title:Text('ZASKIA ${UpdateService.version}')),
        _action('Buscar actualizaciones',Icons.system_update,()=>_run(()async{
          final update=await UpdateService.check();if(mounted)setState(()=>_update=update);
          if(update==null&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('No hay una versión más reciente disponible.'))));
        })),
        if(_update!=null)_action('Descargar actualización',Icons.download,()=>_openUrl(_update!['url'] as String),subtitle:_update!['version'] as String),
        _action('Abrir versiones publicadas',Icons.open_in_new,()=>_openUrl(UpdateService.releases)),
        Text(S.t('La instalación de actualizaciones es manual.')),
      ],[]),
      _section('Diagnóstico',[
        _action('Ver registro de errores',Icons.bug_report_outlined,()=>_run(()async{
          final log=await DiagnosticLog.read();if(!mounted)return;
          await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('Diagnóstico')),content:SingleChildScrollView(child:SelectableText(log.isEmpty?S.t('Sin errores registrados'):log)),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('Cerrar')))]));
        })),
        _action('Copiar información técnica',Icons.copy,()=>_run(()async{
          await Clipboard.setData(ClipboardData(text:'ZASKIA ${UpdateService.version}\n${_device.entries.map((e)=>'${e.key}: ${e.value}').join('\n')}\n${await DiagnosticLog.read()}'));
        })),
        Text(S.t('El registro no guarda mensajes, respuestas ni credenciales.')),
      ],[]),
    ]))),
  ));
}
