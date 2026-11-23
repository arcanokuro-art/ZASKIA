import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/runtime/model_runtime.dart';
import 'package:zaskia/settings/app_settings.dart';

void main() {
  test('lists models and consumes streamed chat from an HTTP engine', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final folder=await Directory.systemTemp.createTemp('zaskia-inference-settings-');
    addTearDown(()=>folder.delete(recursive:true));
    final settings=AppSettings(file:File('${folder.path}/settings.json'));
    await settings.update({'temperature':0.2,'context':4096,'threads':2,'maxTokens':128});
    final runtime = ModelRuntime(settings:settings);
    runtime.configure('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      if (request.uri.path == '/api/tags') {
        request.response.write(jsonEncode({'models': [{'name': 'test:small', 'size': 100}]}));
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['model'], 'test:small');
        expect(body['options'],containsPair('temperature',0.2));
        expect(body['options'],containsPair('num_ctx',4096));
        expect(body['options'],containsPair('num_thread',2));
        expect(body['options'],containsPair('num_predict',128));
        request.response.write('${jsonEncode({'message': {'content': 'Hola '}, 'done': false})}\n');
        request.response.write('${jsonEncode({'message': {'content': 'mundo'}, 'done': true})}\n');
      }
      await request.response.close();
    });
    expect((await runtime.models()).single['name'], 'test:small');
    final packets = await runtime.stream('/api/chat', {'model': 'test:small'}).toList();
    expect(packets.map((item) => item['message']['content']).join(), 'Hola mundo');
    expect(() => runtime.configure('file:///private'), throwsFormatException);
  });
  test('network permission blocks requests before connecting',()async{
    final root=await Directory.systemTemp.createTemp('zaskia-policy-');
    addTearDown(()=>root.delete(recursive:true));
    final settings=AppSettings(file:File('${root.path}/settings.json'));
    await settings.set('allowNetwork',false);
    final runtime=ModelRuntime(settings:settings);
    runtime.configure('http://127.0.0.1:1');
    await expectLater(runtime.models(),throwsStateError);
    await expectLater(runtime.stream('/api/chat',{'messages':[]}).toList(),throwsStateError);
  });

}
