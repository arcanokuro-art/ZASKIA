import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/runtime/downloaded_models.dart';

void main() {
  test('discovers previous downloads and ignores partial files', () async {
    final root = await Directory.systemTemp.createTemp('models-test-');
    addTearDown(() => root.delete(recursive: true));
    final nested = await Directory('${root.path}/author--model/revision').create(recursive: true);
    final model = await File('${nested.path}/model.gguf').writeAsBytes([71, 71, 85, 70]);
    await File('${nested.path}/partial.gguf.part').writeAsBytes([71]);
    final library = DownloadedModels(directory: root);
    expect((await library.list()).map((item) => item.path), [model.path]);
    expect(library.singleFile(File('${nested.path}/model-00001-of-00002.gguf')), false);
  });

  test('copies valid imports and rejects invalid files', () async {
    final root = await Directory.systemTemp.createTemp('models-test-');
    addTearDown(() => root.delete(recursive: true));
    final library = DownloadedModels(directory: Directory('${root.path}/library'));
    final source = await File('${root.path}/source.gguf').writeAsBytes([71, 71, 85, 70, 3, 0, 0, 0]);
    final imported = await library.import(source.path);
    await source.delete();
    expect(await imported.readAsBytes(), [71, 71, 85, 70, 3, 0, 0, 0]);
    final invalid = await File('${root.path}/invalid.gguf').writeAsString('HTML');
    await expectLater(library.import(invalid.path), throwsFormatException);
    expect((await library.list()).length, 1);
  });
}
