import 'dart:math';
import 'hardware_snapshot.dart';

class HardwareAdvice {
  const HardwareAdvice({required this.threads,required this.context,required this.maxTokens,
    required this.weightBudgetBytes,required this.memoryKnown,required this.modelMayExceedBudget});
  final int threads,context,maxTokens;
  final int? weightBudgetBytes;
  final bool memoryKnown,modelMayExceedBudget;
  Map<String,dynamic> get settings=>{'threads':threads,'context':context,'maxTokens':maxTokens};
  Map<String,dynamic> toJson()=>{...settings,'weightBudgetBytes':weightBudgetBytes,
    'memoryKnown':memoryKnown,'modelMayExceedBudget':modelMayExceedBudget};
}

class HardwareAdvisor {
  static const gib=1024*1024*1024;
  static HardwareAdvice recommend(HardwareSnapshot h,{int? modelBytes}) {
    final available=h.availableMemory;
    // Total RAM alone is not free RAM: use only a conservative fraction when needed.
    final budget=available!=null?(available*0.55).floor():h.totalMemory!=null?(h.totalMemory!*0.25).floor():null;
    final reference=available??(h.totalMemory==null?null:h.totalMemory!~/2);
    var context=reference==null?1024:reference<2*gib?512:reference<4*gib?1024:reference<8*gib?2048:4096;
    final tooLarge=budget!=null&&modelBytes!=null&&modelBytes>budget;
    if(tooLarge)context=512;
    var threads=h.os=='android'?max(1,h.usableCores~/2):max(1,h.usableCores-1);
    threads=min(4,threads);
    if(reference!=null&&reference<gib)threads=1;
    return HardwareAdvice(threads:threads,context:context,maxTokens:min(512,context~/2),
      weightBudgetBytes:budget,memoryKnown:available!=null,modelMayExceedBudget:tooLarge);
  }
}
