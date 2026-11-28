import 'dart:io';

import '../storage/model_storage.dart';

class DownloadedModels {
  DownloadedModels({this.directory});
  final Directory? directory;

  Future<List<File>> list({bool includeExternal=false}) async {
    final files = <File>[];
    for (final root in directory != null ? [directory!] : await ModelStorage.roots()) {
    if (!await root.exists()) continue;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File && (entry.path.toLowerCase().endsWith('.gguf') || includeExternal && RegExp(r'\.(safetensors|onnx|bin|pt|pth|model)$',caseSensitive:false).hasMatch(entry.path))) files.add(entry);
    }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  String name(File file) => file.uri.pathSegments.last;

  bool singleFile(File file) => !RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false)
      .hasMatch(name(file));

  Future<File> import(String source) async {
    final input = await File(source).open();
    try {
      if (String.fromCharCodes(await input.read(4)) != 'GGUF') {
        throw const FormatException('Elige un archivo GGUF válido.');
      }
    } finally {
      await input.close();
    }
    final root = directory ?? await ModelStorage.root();
    final imports = await Directory('${root.path}/imports').create(recursive: true);
    final folder = await imports.createTemp('model-');
    final name = File(source).uri.pathSegments.last;
    final target = File('${folder.path}/$name');
    try {
      await File(source).copy('${target.path}.part');
      return await File('${target.path}.part').rename(target.path);
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    }
  }
}
