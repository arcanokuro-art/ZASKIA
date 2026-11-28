import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/media/engine_http.dart';
import 'package:zaskia/media/comfy_engine.dart';
import 'package:zaskia/media/voice_engine.dart';
import 'package:zaskia/media/media_store.dart';
void main(){
  test('workflow substitution preserves numeric types and rejects visual JSON',(){
    expect(()=>ComfyEngine.parseWorkflow('{"nodes":[]}'),throwsFormatException);
    final w=ComfyEngine.parseWorkflow('{"1":{"class_type":"Test","inputs":{"seed":"{{seed}}","text":"say {{prompt}}"}}}');
    final map=ComfyEngine.substitute(w,{'seed':42,'prompt':'hola "mundo"'});
    expect(map['1']['inputs']['seed'],42);expect(map['1']['inputs']['text'],'say hola "mundo"');
    expect(()=>EngineHttp.validateAddress('file:///tmp'),throwsFormatException);
    expect(()=>EngineHttp.validateAddress('http://user:secret@host'),throwsFormatException);
  });
  test('ComfyUI job validates nodes, polls completion and saves image/audio/video',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);addTearDown(()=>server.close(force:true));
    server.listen((r)async{
      r.response.headers.contentType=ContentType.json;
      switch(r.uri.path){
        case '/object_info':r.response.write(jsonEncode({'Save':{}}));
        case '/prompt':final body=jsonDecode(await utf8.decoder.bind(r).join()) as Map;expect(body['prompt']['1']['class_type'],'Save');r.response.write('{"prompt_id":"job1"}');
        case '/history/job1':r.response.write(jsonEncode({'job1':{'status':{'completed':true,'status_str':'success'},'outputs':{'1':{'images':[{'filename':'img.png','type':'output'}],'audio':[{'filename':'music.flac'}],'videos':[{'filename':'clip.mp4'}]}}}}));
        case '/view':r.response.headers.contentType=ContentType.binary;r.response.add([1,2,3,4]);
      }
      await r.response.close();
    });
    final http=EngineHttp('http://127.0.0.1:${server.port}');addTearDown(http.close);
    final files=await ComfyEngine(http).generate({'1':{'class_type':'Save','inputs':{}}},root);
    expect(files.length,3);for(final f in files){expect(await f.length(),4);}
  });
  test('ComfyUI missing nodes fail before submitting and errors are not successes',()async{
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);addTearDown(()=>server.close(force:true));
    server.listen((r)async{expect(r.uri.path,'/object_info');r.response.write('{}');await r.response.close();});
    final http=EngineHttp('http://127.0.0.1:${server.port}');addTearDown(http.close);
    await expectLater(ComfyEngine(http).generate({'1':{'class_type':'Missing','inputs':{}}},Directory.systemTemp),throwsStateError);
  });
  test('voice synthesis saves binary and transcription sends multipart audio',()async{
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));final source=File('${root.path}/input.wav');await source.writeAsBytes([82,73,70,70]);
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);addTearDown(()=>server.close(force:true));
    server.listen((r)async{
      if(r.uri.path=='/v1/audio/speech'){final body=jsonDecode(await utf8.decoder.bind(r).join()) as Map;expect(body['response_format'],'wav');expect(body['model'],'piper');r.response.headers.contentType=ContentType('audio','wav');r.response.add([82,73,70,70]);}
      else{expect(r.headers.contentType!.mimeType,'multipart/form-data');final body=await utf8.decoder.bind(r).join();expect(body,contains('name="model"'));expect(body,contains('whisper'));r.response.write('{"text":"hola"}');}
      await r.response.close();
    });
    final http=EngineHttp('http://127.0.0.1:${server.port}');addTearDown(http.close);final voice=VoiceEngine(http);
    expect(await (await voice.speak('hola','piper','alloy',File('${root.path}/speech.wav'))).length(),4);
    expect(await voice.transcribe(source,'whisper'),'hola');
  });
  test('network policy blocks media and gallery survives reload',()async{
    final http=EngineHttp('http://127.0.0.1:1',allowed:false);addTearDown(http.close);await expectLater(http.json('GET','/object_info'),throwsStateError);
    final root=await Directory.systemTemp.createTemp();addTearDown(()=>root.delete(recursive:true));final store=MediaStore(directory:root);final job=await store.create('music','piano');final data=await store.read(job);await store.record(job,{...data,'status':'Guardado','files':['music.flac']});expect((await MediaStore(directory:root).list()).single['kind'],'music');
  });
}
