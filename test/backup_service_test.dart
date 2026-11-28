import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/storage/backup_service.dart';
import 'package:zaskia/workspace/project_store.dart';

void main(){
  test('backup survives original removal and restores attachments to new owned paths',()async{
    final root=await Directory.systemTemp.createTemp('zaskia-backup-test-');
    addTearDown(()=>root.delete(recursive:true));
    final store=ProjectStore(directory:Directory('${root.path}/projects'));
    final p=await store.create('Original');
    final source=await File('${root.path}/text.txt').writeAsString('contenido de prueba');
    final attachment=await store.copyAttachment(p.id,source.path);
    await store.save(Project(p.id,p.name,1,{'draft':'Hola','messages':[],
      'branches':[{'created':1,'messages':[{'attachments':[{'name':'text.txt','path':attachment,'image':false}]}]}],
      'references':[{'name':'text.txt','path':attachment,'image':false,'selected':true}]},options:{'pinned':true}));
    final backup='${root.path}/backup.zaskia';
    await BackupService.export(backup,projectStore:store);
    await store.remove(p.id);await source.delete();
    await store.create('Conservar');
    expect(await BackupService.restore(backup,projectStore:store,temporaryDirectory:root),1);
    final restored=(await store.list()).firstWhere((v)=>v.name=='Original');
    final path=(restored.data['references'] as List).single['path'] as String;
    expect(path, isNot(attachment));
    expect(await File(path).readAsString(),'contenido de prueba');
    final branchPath=restored.data['branches'][0]['messages'][0]['attachments'][0]['path'];
    expect(branchPath,path);
    expect(restored.pinned,true);
    expect((await store.list()).any((v)=>v.name=='Conservar'),true);
    final invalid=await File('${root.path}/invalid.zaskia').writeAsBytes(gzip.encode(utf8.encode('{"format":"other"}')));
    await expectLater(BackupService.restore(invalid.path,projectStore:store,temporaryDirectory:root),throwsFormatException);
    expect((await store.list()).length,2);
  });
}
