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
    return [current, if (current.path != legacy.path) legacy];
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
        if (f is File && f.path.endsWith('.part')) { await f.delete(); count++; }
      }
    }
    return count;
  }
}
