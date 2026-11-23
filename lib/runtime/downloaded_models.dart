import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DownloadedModels {
  Future<List<File>> list() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/huggingface');
    if (!await root.exists()) return [];
    final files = <File>[];
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File && entry.path.toLowerCase().endsWith('.gguf')) files.add(entry);
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
    final support = await getApplicationSupportDirectory();
    final directory = await Directory('${support.path}/huggingface/imports').create(recursive: true);
    final folder = await directory.createTemp('model-');
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
