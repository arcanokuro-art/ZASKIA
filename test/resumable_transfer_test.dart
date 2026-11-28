import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/storage/resumable_transfer.dart';
import 'package:zaskia/storage/download_manager.dart';
import 'package:zaskia/settings/app_settings.dart';
void main(){
  test('resumes a validated range and verifies the completed SHA-256',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));
    final file=File('${root.path}/model.part');await file.writeAsString('GGUF');
    final bytes=utf8.encode('GGUF-model-data');
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);addTearDown(()=>server.close(force:true));
    server.listen((r)async{expect(r.headers.value('range'),'bytes=4-');r.response.statusCode=206;r.response.headers.set('content-range','bytes 4-${bytes.length-1}/${bytes.length}');r.response.add(bytes.sublist(4));await r.response.close();});
    await ResumableTransfer().fetch(Uri.parse('http://127.0.0.1:${server.port}'),file,expectedSize:bytes.length,sha:sha256.convert(bytes).toString(),gguf:true);
    expect(await file.readAsBytes(),bytes);
  });
  test('ignored range restarts and does not concatenate old bytes',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));final f=File('${root.path}/part');await f.writeAsString('GGUF');
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);addTearDown(()=>server.close(force:true));
    server.listen((r)async{r.response.write('GGUF-hello');await r.response.close();});
    await ResumableTransfer().fetch(Uri.parse('http://127.0.0.1:${server.port}'),f,gguf:true);expect(await f.readAsString(),'GGUF-hello');
  });
  test('wrong hash deletes corrupt partial and mismatched ranges cannot append',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));final f=File('${root.path}/part');await f.writeAsString('GGUF');
    await expectLater(ResumableTransfer().fetch(Uri.parse('http://127.0.0.1:1'),f,expectedSize:4,sha:'0'*64),throwsFormatException);expect(await f.exists(),false);
    await f.writeAsString('GGUF');final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);addTearDown(()=>server.close(force:true));
    server.listen((r)async{r.response.statusCode=206;r.response.headers.set('content-range','bytes 0-3/8');r.response.write('oops');await r.response.close();});
    await expectLater(ResumableTransfer().fetch(Uri.parse('http://127.0.0.1:${server.port}'),f,expectedSize:8),throwsFormatException);expect(await f.readAsString(),'GGUF');
  });
  test('persisted queue restores unfinished files paused and rejects traversal',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));
    final state=File('${root.path}/queue.json');final settings=AppSettings(file:File('${root.path}/settings.json'));await settings.set('allowNetwork',false);
    final manager=DownloadManager(stateFile:state,settings:settings,root:root);addTearDown(manager.dispose);
    await manager.enqueue('org/model','a'*40,{'rfilename':'part/model.gguf'});
    final restored=DownloadManager(stateFile:state,settings:settings,root:root);addTearDown(restored.dispose);await restored.initialize();
    expect(restored.tasks.single.paused,true);expect(restored.activeCount,0);
    await expectLater(manager.enqueue('org/model','a'*40,{'rfilename':'../secret'}),throwsFormatException);
  });
}
