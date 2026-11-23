import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/hardware/hardware_snapshot.dart';
import 'package:zaskia/hardware/hardware_advisor.dart';
import 'package:zaskia/settings/app_settings.dart';

void main(){
  test('process ABI distinguishes 32 bit, ARM64 and x86-64 without brand guesses',(){
    expect(HardwareSnapshot.architectureOf('linux_x64'),'x86-64');
    expect(HardwareSnapshot.architectureOf('android_arm64'),'ARM64');
    expect(HardwareSnapshot.architectureOf('android_arm'),'ARM (32-bit)');
    expect(HardwareSnapshot.architectureOf('mystery'),'unknown');
  });
  test('probe respects cgroup limits and does not invent missing Android RAM',()async{
    final values=<String,String>{
      '/proc/meminfo':'MemTotal: 16777216 kB\nMemAvailable: 12582912 kB\n',
      '/proc/cpuinfo':'model name : Test CPU\nflags : sse4_2 avx avx2 not_a_real_flag\n',
      '/sys/fs/cgroup/memory.max':'2147483648',
      '/sys/fs/cgroup/memory.current':'1073741824',
      '/sys/fs/cgroup/cpu.max':'150000 100000',
    };
    final h=await HardwareProbe.read(reader:(path)async=>values[path],os:'linux',abi:'linux_x64',cores:16);
    expect(h.totalMemory,2*HardwareAdvisor.gib);
    expect(h.availableMemory,HardwareAdvisor.gib);
    expect(h.usableCores,2);expect(h.memoryLimited,true);expect(h.nativeSupported,true);
    expect(h.cpuFeatures,['avx','avx2','sse4_2']);
    final missing=await HardwareProbe.read(reader:(_)async=>null,os:'android',abi:'android_arm64',cores:8);
    expect(missing.totalMemory,isNull);expect(missing.availableMemory,isNull);
    final advice=HardwareAdvisor.recommend(missing);
    expect(advice.context,1024);expect(advice.memoryKnown,false);expect(advice.threads,4);
  });
  test('recommendations reserve RAM and reduce context for oversized weights',()async{
    final h=await HardwareProbe.read(reader:(path)async=>path=='/proc/meminfo'?'MemTotal: 8388608 kB\nMemAvailable: 6291456 kB\n':null,
      os:'linux',abi:'linux_x64',cores:8);
    final advice=HardwareAdvisor.recommend(h,modelBytes:4*HardwareAdvisor.gib);
    expect(advice.modelMayExceedBudget,true);expect(advice.context,512);
    expect(advice.weightBudgetBytes,lessThan(h.availableMemory!));expect(advice.threads,4);
  });
  test('new installations adapt once while existing preferences survive',()async{
    final root=await Directory.systemTemp.createTemp('zaskia-hardware-');
    addTearDown(()=>root.delete(recursive:true));
    final f=File('${root.path}/settings.json');
    final h=await HardwareProbe.read(reader:(path)async=>path=='/proc/meminfo'?'MemTotal: 2097152 kB\nMemAvailable: 1048576 kB\n':null,
      os:'linux',abi:'linux_x64',cores:2);
    final fresh=AppSettings(file:f);await fresh.load();await fresh.initializeHardwareDefaults(hardware:h);
    expect(fresh.get<int>('threads'),1);expect(fresh.get<int>('context'),512);
    expect(fresh.get<String>('language'),'es');
    await fresh.update({'threads':2,'context':8192});
    final existing=AppSettings(file:f);await existing.load();await existing.initializeHardwareDefaults(hardware:h);
    expect(existing.get<int>('context'),8192);expect(existing.get<int>('threads'),2);
  });
}
