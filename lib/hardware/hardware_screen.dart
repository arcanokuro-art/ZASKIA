import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../benchmark/benchmark_runner.dart';
import '../benchmark/benchmark_result.dart';
import '../benchmark/benchmark_store.dart';
import '../diagnostics/diagnostic_log.dart';
import '../localization/strings.dart';
import '../runtime/model_runtime.dart';
import '../settings/app_settings.dart';
import '../updates/update_service.dart';
import 'hardware_snapshot.dart';
import 'hardware_advisor.dart';

class HardwareScreen extends StatefulWidget {
  const HardwareScreen({super.key,required this.runtime,this.probe,this.store});
  final ModelRuntime runtime;
  final Future<HardwareSnapshot> Function()? probe;
  final BenchmarkStore? store;
  @override State<HardwareScreen> createState()=>_HardwareScreenState();
}
class _HardwareScreenState extends State<HardwareScreen> with WidgetsBindingObserver {
  final _runner=BenchmarkRunner();
  late final _store=widget.store??BenchmarkStore();
  HardwareSnapshot? _hardware;
  HardwareAdvice? _advice;
  List<BenchmarkResult> _results=[];
  bool _busy=false,_measuring=false,_cancelRequested=false;
  String _status='';
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_refresh();}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_runner.cancel();super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if((state==AppLifecycleState.hidden||state==AppLifecycleState.paused)&&_measuring){
      _cancelRequested=true;_runner.cancel();widget.runtime.stop();
      if(mounted)setState(()=>_status='Cancelando prueba…');
    }
  }
  Future<void> _refresh()async {
    try {
      final h=await (widget.probe?.call()??HardwareProbe.read());
      int? bytes;
      if(widget.runtime.useLocal&&widget.runtime.localPath.isNotEmpty){try{bytes=await File(widget.runtime.localPath).length();}catch(_) {}}
      final items=await _store.list();
      if(mounted)setState((){_hardware=h;_advice=HardwareAdvisor.recommend(h,modelBytes:bytes);_results=items;});
    }catch(e){await DiagnosticLog.record('hardware-probe',e);if(mounted)setState(()=>_status='No se pudo leer la información del equipo.');}
  }
  String _memory(int? bytes)=>bytes==null?S.t('No disponible'):'${(bytes/1073741824).toStringAsFixed(2)} GiB';
  String _number(dynamic value)=>value is num&&value.isFinite?value.toStringAsFixed(2):'—';
  Widget _row(String title,String value)=>ListTile(title:Text(S.t(title)),subtitle:SelectableText(value));
  Widget _card(String title,List<Widget> children)=>Card(margin:const EdgeInsets.only(bottom:20),child:Padding(
    padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(S.t(title),style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),...children])));
  Future<void> _apply()async {
    final advice=_advice;if(advice==null||_busy)return;
    setState(()=>_busy=true);
    try{
      await AppSettings.instance.update({...advice.settings,'profile':'hardware'});
      if(mounted)setState(()=>_status='Ajustes recomendados aplicados. El modelo se recargará en el próximo uso.');
    }catch(e){await DiagnosticLog.record('hardware-settings',e);if(mounted)setState(()=>_status='No se pudo completar la operación.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _measure()async {
    if(_busy||!widget.runtime.ready||widget.runtime.isBusy)return;
    setState((){_busy=true;_measuring=true;_cancelRequested=false;_status='Prueba en curso…';});
    try {
      final h=await (widget.probe?.call()??HardwareProbe.read());
      if(!mounted)return;
      final runtime=widget.runtime;
      await runtime.prepareConfiguration();
      final configuration=<String,dynamic>{...runtime.configuration,'maxTokens':128,'temperature':0.0};
      final metadata=<String,dynamic>{'appVersion':UpdateService.version,'hardware':h.toJson(),
        'engine':runtime.engineStatus,'configuration':configuration,
        'initialLoadState':runtime.useLocal?(runtime.modelLoaded?'prepared':'load-required'):'external-unknown'};
      if(_cancelRequested)throw BenchmarkCancelled();
      final result=await _runner.run(metadata:metadata,stop:runtime.stop,generate:()=>runtime.stream('/api/chat',{
        'model':runtime.model,'messages':[{'role':'user','content':BenchmarkRunner.prompt}],
        'stream':true,'think':false,'options':{'num_predict':128,'temperature':0.0},
      }));
      if(_cancelRequested)throw BenchmarkCancelled();
      result.data['engineAfter']=runtime.engineStatus;
      await _store.save(result);
      final history=await _store.list();
      if(mounted)setState((){_results=history;_hardware=h;_status='Prueba terminada y guardada.';});
    }on BenchmarkCancelled {
      if(mounted)setState(()=>_status='Prueba cancelada. No se guardó un resultado parcial.');
    }on TimeoutException {
      if(mounted)setState(()=>_status='La prueba superó dos minutos y se detuvo.');
    }catch(e){
      await DiagnosticLog.record('benchmark',e);
      if(mounted)setState(()=>_status='No se pudo completar la prueba. Revisa el modelo y su motor.');
    }finally{if(mounted)setState((){_busy=false;_measuring=false;});}
  }
  void _cancel(){_cancelRequested=true;_runner.cancel();widget.runtime.stop();setState(()=>_status='Cancelando prueba…');}
  Future<void> _export()async {
    if(_busy||_results.isEmpty)return;
    try{
      final folder=await FilePicker.platform.getDirectoryPath();if(folder==null)return;
      await _store.export('$folder/ZASKIA-rendimiento-${DateTime.now().millisecondsSinceEpoch}.json',_results);
      if(mounted)setState(()=>_status='Resultados exportados.');
    }catch(e){await DiagnosticLog.record('benchmark-export',e);if(mounted)setState(()=>_status='No se pudo completar la operación.');}
  }
  Future<void> _copy()async {
    if(_results.isEmpty)return;
    await Clipboard.setData(ClipboardData(text:const JsonEncoder.withIndent('  ').convert({
      'format':'ZASKIA-benchmarks-1','results':_results.map((r)=>r.toJson()).toList()})));
    if(mounted)setState(()=>_status='Resultados copiados.');
  }
  @override Widget build(BuildContext context){
    final h=_hardware,advice=_advice,engine=widget.runtime.engineStatus;
    final settings=widget.runtime.configuration;
    return PopScope(canPop:!_busy,child:Scaffold(appBar:AppBar(title:Text(S.t('Mi equipo'))),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:950),child:ListView(
        padding:const EdgeInsets.all(20),children:[
          if(_status.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:16),child:Text(S.t(_status))),
          if(h==null)const LinearProgressIndicator(),
          if(h!=null)_card('Hardware detectado',[
            _row('Sistema',h.os),_row('Arquitectura del proceso',h.architecture),_row('ABI',h.abi),
            _row('Procesador',h.processor??S.t('No disponible')),
            _row('Procesadores lógicos','${h.logicalCores}'),_row('Procesadores utilizables','${h.usableCores}'),
            _row('RAM total',_memory(h.totalMemory)),_row('RAM disponible',_memory(h.availableMemory)),
            _row('Instrucciones detectadas',h.cpuFeatures.isEmpty?S.t('No disponible'):h.cpuFeatures.join(', ')),
            if(h.memoryLimited)Text(S.t('Se detectó un límite de memoria del entorno.')),
            Text(S.t(h.nativeSupported?'Arquitectura cubierta por el motor integrado.':'Este motor integrado no cubre esta combinación de sistema y arquitectura.')),
            TextButton.icon(onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh),label:Text(S.t('Actualizar información del equipo'))),
          ]),
          _card('Motor seleccionado',[
            _row('Modelo',widget.runtime.ready?widget.runtime.selectedName:S.t('Modelo local sin configurar')),
            _row('Motor',engine['engine'] as String),
            _row('Ejecución',S.t(widget.runtime.useLocal?'En este dispositivo':'Motor externo: hardware y aceleración no verificados')),
            _row('Aceleración',widget.runtime.useLocal?'CPU':S.t('No verificada')),
            if(engine['cpuBackend']!=null)_row('Backend de CPU activo',engine['cpuBackend'] as String),
            if(widget.runtime.useLocal)_row('Modelo preparado',S.t(widget.runtime.modelLoaded?'Sí':'No')),
            _row('Hilos de CPU','${settings['threads']}'),_row('Tamaño del contexto','${settings['context']}'),
            Text(S.t('Detectar instrucciones no significa que el motor utilice todas ellas. GPU y NPU no están activadas en este motor integrado.')),
          ]),
          if(advice!=null)_card('Ajustes sugeridos',[
            _row('Hilos de CPU','${advice.threads}'),_row('Tamaño del contexto','${advice.context}'),
            _row('Longitud máxima de respuesta','${advice.maxTokens}'),
            _row('Presupuesto orientativo para pesos',_memory(advice.weightBudgetBytes)),
            Text(S.t(advice.memoryKnown?'La recomendación usa la RAM disponible en esta lectura.':'RAM disponible desconocida: se usan valores conservadores.')),
            if(advice.modelMayExceedBudget)Text(S.t('El modelo seleccionado supera el presupuesto orientativo. Considera uno más pequeño.')),
            Text(S.t('Es una estimación: el formato, el contexto y la arquitectura del modelo cambian el consumo real.')),
            FilledButton(onPressed:_busy||(!widget.runtime.useLocal&&widget.runtime.ready)?null:_apply,child:Text(S.t('Aplicar ajustes sugeridos'))),
            Text(S.t('Las sugerencias son para el motor integrado de este dispositivo.')),
            Text(S.t('Las instalaciones nuevas reciben valores iniciales adaptados. Los ajustes existentes no se sobrescriben.')),
          ]),
          _card('Prueba de rendimiento',[
            Text(S.t('Prueba opcional con un mensaje fijo y un máximo solicitado de 128 tokens. No usa tu historial ni tu memoria personal.')),
            Text(S.t('El tiempo total y la primera respuesta incluyen la preparación del modelo si era necesaria.')),
            Text(S.t('Una prueba por modelo no garantiza el rendimiento con todas las tareas.')),
            if(!widget.runtime.useLocal)Text(S.t('Con Ollama se mide la conexión y el motor externo, no solo este equipo.')),
            if(_measuring)const LinearProgressIndicator(),
            Wrap(spacing:12,children:[FilledButton.icon(onPressed:_busy||!widget.runtime.ready||widget.runtime.isBusy?null:_measure,
              icon:const Icon(Icons.speed),label:Text(S.t('Iniciar prueba'))),
              if(_measuring)OutlinedButton(onPressed:_cancelRequested?null:_cancel,child:Text(S.t('Detener')))]),
          ]),
          _card('Resultados guardados',[
            Text(S.t('Caracteres/s mide texto Unicode entregado por segundo de tiempo total. Los tokens/s solo aparecen si el motor informa un conteo real.')),
            if(_results.isEmpty)Text(S.t('Todavía no hay resultados.')),
            if(_results.isNotEmpty)SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
              dataRowMinHeight:56,dataRowMaxHeight:96,
              columns:[for(final label in ['Modelo','Equipo','CPU / contexto','Primera respuesta (s)','Total (s)','Caracteres/s','Tokens/s total'])DataColumn(label:Text(S.t(label)))],
              rows:[for(final result in _results.take(10))_resultRow(result)],
            )),
            Text(S.t('Compara el mismo modelo, protocolo, contexto y estado de carga. Los resultados externos incluyen latencia de red.')),
            Wrap(spacing:12,children:[TextButton.icon(onPressed:_busy||_results.isEmpty?null:_export,
              icon:const Icon(Icons.save_alt),label:Text(S.t('Exportar resultados JSON'))),
              TextButton.icon(onPressed:_busy||_results.isEmpty?null:_copy,icon:const Icon(Icons.copy),label:Text(S.t('Copiar resultados')))]),
            Text(S.t('Se guardan hasta 50 pruebas. La tabla muestra las 10 más recientes. No se guarda el texto generado ni la dirección del motor externo.')),
          ]),
        ],
      ))),
    ));
  }
  DataRow _resultRow(BenchmarkResult result){
    final d=result.data;
    final engine=(d['engineAfter']??d['engine']) as Map? ?? {};
    final hardware=d['hardware'] as Map? ?? {};
    final config=d['configuration'] as Map? ?? {};
    return DataRow(cells:[
      DataCell(SizedBox(width:180,child:Text(engine['model']?.toString()??'—',maxLines:2,overflow:TextOverflow.ellipsis))),
      DataCell(SizedBox(width:200,child:Text('${hardware['processor']??hardware['architecture']??'—'}\n${hardware['os']??''}${engine['location']=='external'?' · ${S.t('Externo')}':''}',maxLines:2,overflow:TextOverflow.ellipsis))),
      DataCell(Text('${config['threads']??'—'} / ${config['context']??'—'}')),
      DataCell(Text(_number(d['firstTextSeconds']))),DataCell(Text(_number(d['totalSeconds']))),
      DataCell(Text(_number(d['charactersPerSecond']))),DataCell(Text(_number(d['endToEndTokensPerSecond']))),
    ]);
  }
}
