import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DiagnosticLog {
  static Future<void> record(String event, Object error) async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/diagnostics.log');
      var old = await f.exists() ? await f.readAsString() : '';
      if (old.length > 24000) old = old.substring(old.length-24000);
      // Do not store prompts, file paths, model output, or credentials.
      await f.writeAsString('$old${DateTime.now().toIso8601String()} $event ${error.runtimeType}\n');
    } catch (_) {}
  }
  static Future<String> read() async {
    final f = File('${(await getApplicationSupportDirectory()).path}/diagnostics.log');
    return await f.exists() ? f.readAsString() : '';
  }
}
