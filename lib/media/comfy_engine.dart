import 'dart:convert';
import 'dart:io';
import 'engine_http.dart';

class ComfyEngine {
  ComfyEngine(this.http);
  final EngineHttp http;
  String? jobId;
  static Map<String,dynamic> parseWorkflow(String text) {
    final raw=jsonDecode(text);
    if(raw is! Map)throw const FormatException('Importa un flujo en formato API de ComfyUI.');
    final map=Map<String,dynamic>.from(raw['prompt'] is Map?raw['prompt'] as Map:raw);
    if(map.isEmpty||map.values.any((n)=>n is! Map||n['class_type'] is! String||n['inputs'] is! Map))throw const FormatException('Usa Exportar (API), no el formato visual de ComfyUI.');
    return map;
  }
  static dynamic substitute(dynamic value,Map<String,Object> variables) {
    if(value is Map)return value.map((k,v)=>MapEntry(k,substitute(v,variables)));
    if(value is List)return value.map((v)=>substitute(v,variables)).toList();
    if(value is String){for(final e in variables.entries){if(value=='{{${e.key}}}')return e.value;value=value.replaceAll('{{${e.key}}}',e.value.toString());}}
    return value;
  }
  Future<List<String>> checkpoints()async{
    final result=await http.json('GET','/models/checkpoints');return (result as List).cast<String>();
  }
  Future<Map<String,dynamic>> capabilities()async=>Map<String,dynamic>.from(await http.json('GET','/object_info') as Map);
  static Map<String,dynamic> imageWorkflow({required String checkpoint,required String prompt,String negative='',int seed=0,int width=512,int height=512,int steps=20,double cfg=7,String? image,double denoise=0.7})=>{
    '1':{'class_type':'CheckpointLoaderSimple','inputs':{'ckpt_name':checkpoint}},
    '2':{'class_type':'CLIPTextEncode','inputs':{'text':prompt,'clip':['1',1]}},
    '3':{'class_type':'CLIPTextEncode','inputs':{'text':negative,'clip':['1',1]}},
    if(image==null)'4':{'class_type':'EmptyLatentImage','inputs':{'width':width,'height':height,'batch_size':1}},
    if(image!=null)...{
      '8':{'class_type':'LoadImage','inputs':{'image':image}},
      '4':{'class_type':'VAEEncode','inputs':{'pixels':['8',0],'vae':['1',2]}},
    },
    '5':{'class_type':'KSampler','inputs':{'model':['1',0],'positive':['2',0],'negative':['3',0],'latent_image':['4',0],'seed':seed,'steps':steps,'cfg':cfg,'sampler_name':'euler','scheduler':'normal','denoise':image==null?1.0:denoise}},
    '6':{'class_type':'VAEDecode','inputs':{'samples':['5',0],'vae':['1',2]}},
    '7':{'class_type':'SaveImage','inputs':{'images':['6',0],'filename_prefix':'ZASKIA'}},
  };
  Future<String> upload(File file)async{
    final boundary='Zaskia${DateTime.now().microsecondsSinceEpoch}';
    final r=await http.open('POST','/upload/image',contentType:'multipart/form-data; boundary=$boundary',body:http.multipart(boundary,{'type':'input'},'image',file));
    final map=jsonDecode(await utf8.decoder.bind(r).join()) as Map;
    final folder=map['subfolder'] as String? ?? '';
    return '${folder.isEmpty?'':'$folder/'}${map['name']}';
  }
  Future<List<File>> generate(Map<String,dynamic> workflow,Directory output,{void Function(String)? status,Duration timeout=const Duration(minutes:30)})async{
    final nodes=await capabilities();
    final missing=workflow.values.map((v)=>(v as Map)['class_type']).where((n)=>!nodes.containsKey(n)).toSet();
    if(missing.isNotEmpty)throw StateError('Faltan nodos en el motor: ${missing.join(', ')}');
    final submitted=await http.json('POST','/prompt',body:{'prompt':workflow,'client_id':'zaskia-${DateTime.now().microsecondsSinceEpoch}'});
    if(submitted['error']!=null||submitted['prompt_id'] is! String)throw StateError('El motor rechazó el flujo: ${submitted['node_errors'] ?? submitted['error']}');
    jobId=submitted['prompt_id'] as String;status?.call('En cola');
    final deadline=DateTime.now().add(timeout);
    while(DateTime.now().isBefore(deadline)){
      if(http.cancelled)throw StateError('Operación cancelada.');
      final history=await http.json('GET','/history/$jobId') as Map;
      final job=history[jobId] as Map?;
      if(job!=null){
        final state=job['status'] as Map?;
        if(state?['status_str']=='error')throw StateError('El flujo falló. Revisa los modelos y el registro de ComfyUI.');
        if(state?['completed']==true||state?['status_str']=='success'){
          final results=<File>[];
          final outputs=job['outputs'] as Map? ?? {};
          try{
            for(final raw in outputs.values){
              for(final kind in ['images','audio','gifs','videos']){
                final files=(raw as Map)[kind] as List? ?? [];
                for(final entry in files){
                  if(entry is! Map||entry['filename'] is! String)continue;
                  final name=entry['filename'] as String;
                  final ext=name.split('.').last.toLowerCase();
                  if(!['png','jpg','jpeg','webp','gif','wav','mp3','flac','ogg','mp4','webm','mov'].contains(ext))continue;
                  final response=await http.open('GET','/view',query:{'filename':name,'subfolder':entry['subfolder'] as String? ?? '', 'type':entry['type'] as String? ?? 'output'});
                  results.add(await http.save(response,File('${output.path}/result-${results.length}.$ext')));
                }
              }
            }
            if(results.isEmpty)throw StateError('El flujo terminó sin archivos compatibles. Añade un nodo de guardado.');
            return results;
          }catch(_){for(final f in results){if(await f.exists())await f.delete();}rethrow;}
        }
      }
      status?.call('Procesando en el motor');
      await Future<void>.delayed(const Duration(seconds:1));
    }
    await cancel();throw const HttpException('Tiempo límite del flujo alcanzado.');
  }
  /// Never interrupt another client's active job. Remove only our queued item.
  Future<void> cancel()async{
    final id=jobId;if(id==null){http.cancel();return;}
    final control=EngineHttp(http.base.toString(),allowed:http.allowed);
    http.cancel();
    try{
      final queue=await control.json('GET','/queue') as Map;
      final running=queue['queue_running'] as List? ?? [];
      if(running.any((r)=>r is List && r.length>1 && r[1]==id)){
        await control.json('POST','/interrupt',body:{'prompt_id':id});
      }else{await control.json('POST','/queue',body:{'delete':[id]});}
    }finally{control.close();}
  }
}
