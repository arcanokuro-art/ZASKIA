import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/runtime/model_info.dart';
import 'package:zaskia/runtime/model_compatibility.dart';
import 'package:zaskia/hardware/hardware_snapshot.dart';
import 'package:zaskia/onboarding/starter_catalog.dart';
void main(){
  HardwareSnapshot hardware({String abi='linux_x64',int? available=4*1073741824})=>HardwareSnapshot(os:'linux',abi:abi,logicalCores:4,usableCores:4,capturedAt:DateTime(2026),availableMemory:available);
  ModelInfo model({String path='test.gguf',String architecture='qwen2',int size=429000000,Map<String,String> extra=const {}})=>ModelInfo(path:path,bytes:size,format:'GGUF v3',capabilities:'Texto · arquitectura reconocida',engine:'llama.cpp',metadata:{'Arquitectura':architecture,...extra});
  test('candidate is explicitly provisional and memory pressure warns',(){
    expect(ModelCompatibility.assess(model(),hardware()).state,'candidate');
    expect(ModelCompatibility.assess(model(size:4*1073741824),hardware()).state,'warning');
    expect(ModelCompatibility.assess(model(),hardware(available:null)).state,'unknown');
  });
  test('embeddings, splits, incomplete files and foreign process ABI cannot load',(){
    for(final m in [model(architecture:'bert'),model(extra:{'Número de partes':'2'}),model(extra:{'Lectura':'Error'})]){expect(ModelCompatibility.assess(m,hardware()).blocked,true);}
    expect(ModelCompatibility.assess(model(),hardware(abi:'linux_arm64')).blocked,true);
    expect(ModelCompatibility.assess(model(path:'weights.safetensors'),hardware()).state,'external');
    expect(ModelCompatibility.assess(model(extra:{'Lectura':'Límite de inspección alcanzado'}),hardware()).state,'unknown');
  });
  test('small starter is suggested under low or unknown memory without promising fit',(){
    expect(StarterCatalog.suggest(hardware(available:800000000)),StarterCatalog.models.first);
    expect(StarterCatalog.suggest(hardware(available:null)),StarterCatalog.models.first);
  });
  test('external weight inspection reports engine dependency instead of pretending GGUF',()async{
    final dir=await Directory.systemTemp.createTemp();addTearDown(()=>dir.delete(recursive:true));
    final file=await File('${dir.path}/model.safetensors').writeAsString('weights');final info=await ModelInfo.inspect(file);expect(info.format,'SAFETENSORS');expect(info.engine,'Motor externo');
  });
}
