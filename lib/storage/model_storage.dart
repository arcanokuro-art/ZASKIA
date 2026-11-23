import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../settings/app_settings.dart';

class ModelStorage {
  static Future<Directory> root() async {
    final custom = AppSettings.instance.get<String>('modelFolder');
    final root = custom.isEmpty ? Directory('${(await getApplicationSupportDirectory()).path}/huggingface') : Directory(custom);
    return root.create(recursive:true);
  }
  static Future<List<Directory>> roots() async {
    final legacy = Directory('${(await getApplicationSupportDirectory()).path}/huggingface');
    final current = await root();
    final paths=<String>{current.path,legacy.path,...AppSettings.instance.get<List>('modelFolders').cast<String>()};
    return paths.map(Directory.new).toList();
  }
  static Future<int> size(Directory root) async {
    if (!await root.exists()) return 0;
    var result = 0;
    await for (final f in root.list(recursive:true, followLinks:false)) {
      if (f is File) result += await f.length();
    }
    return result;
  }
  static Future<int> clearPartial() async {
    var count = 0;
    for (final root in await roots()) {
      if (!await root.exists()) continue;
      await for (final f in root.list(recursive:true, followLinks:false)) {
        if (f is! File)continue;
        final relative=f.path.substring(root.path.length+1);
        final managed=RegExp(r'^imports/model-[^/]+/[^/]+\.part$').hasMatch(relative) ||
          RegExp(r'^[^/]+--[^/]+/[0-9a-fA-F]{40}/[^/]+\.gguf\.part$',caseSensitive:false).hasMatch(relative);
        if (managed) { await f.delete(); count++; }
      }
    }
    return count;
  }
}
