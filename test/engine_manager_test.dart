import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/engines/engine_manager.dart';

void main(){
  test('source install pins revision, uses a private venv and publishes after completion',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));final calls=<List<String>>[];
    final manager=EngineManager(directory:root,supported:true,commandRunner:(exe,args,cwd)async{calls.add([exe,...args]);if(args.contains('init'))await Directory('$cwd/source').create();});addTearDown(manager.dispose);
    await manager.install(EngineRelease(EngineKind.comfy,'v1.0.0','a'*40));
    final installed=await manager.installation(EngineKind.comfy);expect(installed!['active']['revision'],'a'*40);expect(calls.any((c)=>c.contains('fetch')&&c.contains('a'*40)),true);expect(calls.any((c)=>c.contains('venv')),true);expect(manager.busy,false);
  });
  test('failed update keeps previous active environment, successful update can roll back',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));var fail=false;
    final manager=EngineManager(directory:root,supported:true,commandRunner:(exe,args,cwd)async{if(fail)throw StateError('dependency error');if(args.contains('init'))await Directory('$cwd/source').create();});addTearDown(manager.dispose);
    await manager.install(EngineRelease(EngineKind.comfy,'v1.0.0','a'*40));fail=true;
    await expectLater(manager.install(EngineRelease(EngineKind.comfy,'v2.0.0','b'*40)),throwsStateError);
    expect((await manager.installation(EngineKind.comfy))!['active']['version'],'v1.0.0');
    fail=false;await manager.install(EngineRelease(EngineKind.comfy,'v2.0.0','b'*40));await manager.rollback(EngineKind.comfy);
    expect((await manager.installation(EngineKind.comfy))!['active']['version'],'v1.0.0');
    expect(await root.list(recursive:true).where((e)=>e is Directory && e.path.split('/').last.startsWith('build-')).length,2);
  });
  test('unsupported platforms reject installation and invalid revisions never publish',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));
    final manager=EngineManager(directory:root,supported:false);addTearDown(manager.dispose);
    await expectLater(manager.install(const EngineRelease(EngineKind.comfy,'v1.0.0','main')),throwsUnsupportedError);
    final test=EngineManager(directory:root,supported:true,commandRunner:(e,a,c)async{});addTearDown(test.dispose);
    await expectLater(test.install(const EngineRelease(EngineKind.comfy,'v1.0.0','main')),throwsFormatException);
    expect(await test.installation(EngineKind.comfy),null);
  });
}
