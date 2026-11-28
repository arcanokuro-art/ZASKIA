import 'dart:convert';
import 'dart:io';
import '../hardware/hardware_snapshot.dart';
import '../hardware/hardware_advisor.dart';

class StarterModel {
  const StarterModel(this.name,this.repo,this.filename,this.approximateBytes);
  final String name,repo,filename;
  final int approximateBytes;
}
class StarterCatalog {
  static const models=[
    StarterModel('Qwen2.5 0.5B Instruct · Q4_K_M','Qwen/Qwen2.5-0.5B-Instruct-GGUF','qwen2.5-0.5b-instruct-q4_k_m.gguf',429000000),
    StarterModel('Qwen2.5 1.5B Instruct · Q4_K_M','Qwen/Qwen2.5-1.5B-Instruct-GGUF','qwen2.5-1.5b-instruct-q4_k_m.gguf',1120000000),
    StarterModel('Qwen2.5 3B Instruct · Q4_K_M','Qwen/Qwen2.5-3B-Instruct-GGUF','qwen2.5-3b-instruct-q4_k_m.gguf',2100000000),
  ];
  static StarterModel suggest(HardwareSnapshot hardware){
    final budget=HardwareAdvisor.recommend(hardware).weightBudgetBytes??models.first.approximateBytes;
    return models.reversed.firstWhere((m)=>m.approximateBytes<=budget,orElse:()=>models.first);
  }
  static Future<Map<String,dynamic>> resolve(StarterModel model,{required bool allowNetwork})async{
    if(!allowNetwork)throw StateError('Acceso a red desactivado.');
    final client=HttpClient()..connectionTimeout=const Duration(seconds:15);
    try{
      final r=await (await client.getUrl(Uri.https('huggingface.co','/api/models/${model.repo}',{'blobs':'true'}))).close().timeout(const Duration(seconds:30));
      if(r.statusCode!=200)throw HttpException('Hugging Face: HTTP ${r.statusCode}');
      final text=StringBuffer();var size=0;
      await for(final chunk in r.transform(utf8.decoder).timeout(const Duration(seconds:30))){size+=chunk.length;if(size>4*1024*1024)throw const FormatException('Catálogo demasiado grande.');text.write(chunk);}
      final json=jsonDecode(text.toString()) as Map;
      final revision=json['sha'] as String;
      if(!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision))throw const FormatException('Revisión del modelo no válida.');
      final file=(json['siblings'] as List).cast<Map>().firstWhere((f)=>f['rfilename']==model.filename);
      return {'revision':revision,'metadata':Map<String,dynamic>.from(file),'license':(json['cardData'] as Map?)?['license']?.toString()??'Consultar ficha del modelo'};
    }finally{client.close(force:true);}
  }
}
