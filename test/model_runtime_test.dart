import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/runtime/model_runtime.dart';

void main() {
  test('lists models and consumes streamed chat from an HTTP engine', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final runtime = ModelRuntime();
    runtime.configure('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      if (request.uri.path == '/api/tags') {
        request.response.write(jsonEncode({'models': [{'name': 'test:small', 'size': 100}]}));
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['model'], 'test:small');
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
}
