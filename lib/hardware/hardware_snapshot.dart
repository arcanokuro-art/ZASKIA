import 'dart:ffi';
import 'dart:io';
import 'dart:math';

typedef HardwareRead = Future<String?> Function(String path);

/// Process ABI and measurable host resources. Missing sensors stay unknown.
class HardwareSnapshot {
  const HardwareSnapshot({required this.os,required this.abi,required this.logicalCores,
    required this.usableCores,required this.capturedAt,this.processor,this.totalMemory,
    this.availableMemory,this.cpuFeatures=const [],this.memoryLimited=false});
  final String os,abi;
  final int logicalCores,usableCores;
  final DateTime capturedAt;
  final String? processor;
  final int? totalMemory,availableMemory;
  final List<String> cpuFeatures;
  final bool memoryLimited;
  String get architecture => architectureOf(abi);
  bool get nativeSupported => (os=='linux' && architecture=='x86-64') ||
      (os=='android' && architecture=='ARM64');
  static String architectureOf(String abi) {
    final name=abi.toLowerCase();
    if(name.endsWith('_x64'))return 'x86-64';
    if(name.endsWith('_arm64')||name.endsWith('_arm64e'))return 'ARM64';
    if(name.endsWith('_ia32'))return 'x86 (32-bit)';
    if(name.endsWith('_arm'))return 'ARM (32-bit)';
    return 'unknown';
  }
  Map<String,dynamic> toJson()=>{'os':os,'abi':abi,'architecture':architecture,
    'logicalCores':logicalCores,'usableCores':usableCores,'processor':processor,
    'totalMemoryBytes':totalMemory,'availableMemoryBytes':availableMemory,
    'cpuFeatures':cpuFeatures,'memoryLimited':memoryLimited,
    'capturedAt':capturedAt.toUtc().toIso8601String()};
}

class HardwareProbe {
  static Future<String?> _file(String path)async {
    try{return await File(path).readAsString();}catch(_){return null;}
  }
  static bool supportsNativeRuntime() {
    final arch=HardwareSnapshot.architectureOf(Abi.current().toString());
    return (Platform.isLinux&&arch=='x86-64')||(Platform.isAndroid&&arch=='ARM64');
  }
  static Future<HardwareSnapshot> read({HardwareRead? reader,String? os,String? abi,int? cores})async {
    final read=reader??_file;
    final system=os??Platform.operatingSystem;
    final currentAbi=abi??Abi.current().toString();
    final logical=max(1,cores??Platform.numberOfProcessors);
    int usable=logical;
    int? total,available;
    bool limited=false;
    String? processor;
    final features=<String>{};
    if(system=='linux'||system=='android') {
      final memory=await read('/proc/meminfo');
      int? kb(String name) {
        final match=RegExp('^$name:\\s+(\\d+)\\s+kB',multiLine:true).firstMatch(memory??'');
        final amount=int.tryParse(match?[1]??'');
        return amount==null?null:amount*1024;
      }
      total=kb('MemTotal');available=kb('MemAvailable');
      final cpu=await read('/proc/cpuinfo')??'';
      for(final line in cpu.split('\n')) {
        final colon=line.indexOf(':');if(colon<0)continue;
        final key=line.substring(0,colon).trim().toLowerCase();
        final value=line.substring(colon+1).trim();
        if((key=='model name'||key=='hardware')&&value.isNotEmpty)processor??=value;
        if(key=='flags'||key=='features')features.addAll(value.toLowerCase().split(RegExp(r'\s+')));
      }
      if(system=='linux') {
        final maxText=(await read('/sys/fs/cgroup/memory.max'))?.trim();
        final maxMemory=int.tryParse(maxText??'');
        final used=int.tryParse((await read('/sys/fs/cgroup/memory.current'))?.trim()??'');
        if(maxMemory!=null&&maxMemory>0 && (total==null||maxMemory<total)) {
          total=maxMemory;limited=true;
          if(used!=null)available=min(available??maxMemory,max(0,maxMemory-used));
          else available=null;
        }
        final quota=(await read('/sys/fs/cgroup/cpu.max'))?.trim().split(RegExp(r'\s+'));
        if(quota!=null&&quota.length==2){
          final count=int.tryParse(quota[0]),period=int.tryParse(quota[1]);
          if(count!=null&&count>0&&period!=null&&period>0)usable=min(logical,max(1,(count/period).ceil()));
        }
      }
      if(system=='android'&&reader==null) {
        try {
          final result=await Process.run('/system/bin/getprop',['ro.soc.model']).timeout(const Duration(seconds:1));
          final model=result.stdout.toString().trim();
          if(result.exitCode==0&&model.isNotEmpty)processor=model;
        }catch(_){}
      }
    }
    if(total!=null&&total<=0)total=null;
    if(available!=null)available=available.clamp(0,total??available).toInt();
    return HardwareSnapshot(os:system,abi:currentAbi,logicalCores:logical,usableCores:usable,
      capturedAt:DateTime.now(),processor:processor,totalMemory:total,availableMemory:available,
      cpuFeatures:features.where((f)=>['sse4_2','avx','avx2','avx512f','fma','neon','asimd','asimddp','dotprod','i8mm'].contains(f)).toList()..sort(),
      memoryLimited:limited);
  }
}
