import 'dart:io';
import '../lib/runtime/linux_text_engine.dart';

Future<void> main(List<String> args) async {
  final engine = LinuxTextEngine(executable: File(args[0]).absolute.path);
  try {
    await engine.load(File(args[1]).absolute.path);
    var tokens = 0;
    var finished = false;
    await for (final event in engine.chat([{'role': 'user', 'content': 'Once upon a time'}])) {
      if ((event['message'] as Map)['content'] != '') tokens++;
      if (event['done'] == true) finished = true;
    }
    if (tokens == 0 || !finished) throw StateError('No streamed inference result.');
    // A second generation exercises stopping and reusing the same process.
    await for (final event in engine.chat([{'role': 'user', 'content': 'A little cat'}])) {
      if ((event['message'] as Map)['content'] != '') { engine.stop(); break; }
    }
    print('Linux engine: model loaded, streaming generated, stop completed.');
  } finally {
    await engine.unload();
  }
  if (engine.loadedPath != null) throw StateError('Model was not unloaded.');
}
