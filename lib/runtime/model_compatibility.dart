import 'dart:math';
import '../hardware/hardware_snapshot.dart';
import 'model_info.dart';

/// A preflight estimate, never a promise that a file will successfully load.
class ModelCompatibility {
  const ModelCompatibility({required this.state,required this.reason,required this.engine,this.estimatedBytes,this.availableBytes});
  final String state,reason,engine;
  final int? estimatedBytes,availableBytes;
  bool get blocked=>state=='unsupported';
  static ModelCompatibility assess(ModelInfo info,HardwareSnapshot hardware,{int context=2048}){
    final ext=info.path.split('.').last.toLowerCase();
    final free=hardware.availableMemory;
    ModelCompatibility result(String state,String reason,String engine,{int? estimate})=>ModelCompatibility(state:state,reason:reason,engine:engine,estimatedBytes:estimate,availableBytes:free);
    if(ext!='gguf')return result('external','Este formato requiere un motor y sus componentes compatibles.','Motor externo');
    if(!info.format.startsWith('GGUF v')||info.metadata.containsKey('Lectura'))return result('unsupported','El archivo está incompleto o no se pudo verificar.','llama.cpp');
    if(int.tryParse(info.metadata['Número de partes']??'1')!=1||RegExp(r'-\d{5}-of-\d{5}\.gguf$',caseSensitive:false).hasMatch(info.path))return result('unsupported','El motor integrado aún no carga modelos divididos.','Motor externo');
    final arch=info.metadata['Arquitectura']??'';
    if(['bert','nomic-bert','t5','clip','whisper'].contains(arch))return result('unsupported','Este modelo no es un modelo de conversación compatible.','Motor especializado');
    if(!hardware.nativeSupported)return result('unsupported','La compilación integrada no admite esta plataforma o arquitectura.','Motor externo');
    final recognized=info.capabilities.startsWith('Texto');
    if(!recognized)return result('unknown','La arquitectura no está verificada. La carga puede fallar.','llama.cpp');
    // Model weights + runtime buffers + a deliberately broad context allowance.
    // KV cache size depends on architecture; this is a screening estimate only.
    final estimate=((info.bytes*1.25).ceil()+max(256*1024*1024,context*256*1024)).toInt();
    if(free!=null&&estimate>free*0.8)return result('warning','La memoria libre parece insuficiente. Prueba un modelo menor o un contexto más corto.','llama.cpp',estimate:estimate);
    if(free==null)return result('unknown','No se conoce la memoria libre. Verifica cargando el modelo.','llama.cpp',estimate:estimate);
    return result('candidate','Candidato para este equipo. La compatibilidad final se confirma al cargar.','llama.cpp',estimate:estimate);
  }
  static String bytes(int? value)=>value==null?'—':'${(value/1073741824).toStringAsFixed(2)} GiB';
}
