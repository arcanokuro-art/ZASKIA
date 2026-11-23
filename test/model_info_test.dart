import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/runtime/model_info.dart';

void main() {
  test('reads UTF-8 names and architecture without reading weights', () async {
    final root = await Directory.systemTemp.createTemp('gguf-info-');
    addTearDown(() => root.delete(recursive: true));
    final bytes = BytesBuilder();
    void number(int value, int size) {
      final data = ByteData(size);
      if (size == 4) {
        data.setUint32(0, value, Endian.little);
      } else {
        data.setUint64(0, value, Endian.little);
      }
      bytes.add(data.buffer.asUint8List());
    }
    void string(String value) {
      final encoded = utf8.encode(value);
      number(encoded.length, 8);
      bytes.add(encoded);
    }
    bytes.add(ascii.encode('GGUF'));
    number(3, 4);
    number(1, 8);
    number(2, 8);
    string('general.name');
    number(8, 4);
    string('Modelo español');
    string('general.architecture');
    number(8, 4);
    string('qwen3');
    final file = await File('${root.path}/model.gguf').writeAsBytes(bytes.takeBytes());
    final info = await ModelInfo.inspect(file);
    expect(info.metadata['Nombre del modelo'], 'Modelo español');
    expect(info.metadata['Arquitectura'], 'qwen3');
    expect(info.format, 'GGUF v3');
    expect(info.capabilities, contains('Texto'));
    expect(info.bytes, await file.length());
    expect(info.path, file.path);
  });

  test('marks truncated or foreign files as unverified', () async {
    final root = await Directory.systemTemp.createTemp('gguf-info-');
    addTearDown(() => root.delete(recursive: true));
    final file = await File('${root.path}/bad.gguf').writeAsString('HTML');
    final info = await ModelInfo.inspect(file);
    expect(info.capabilities, 'Por comprobar');
    expect(info.metadata['Lectura'], isNotNull);
  });
}
