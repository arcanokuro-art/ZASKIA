import 'dart:io';
import '../lib/runtime/linux_text_engine.dart';
import '../lib/benchmark/benchmark_runner.dart';

Future<void> main(List<String> args) async {
  final engine = LinuxTextEngine(executable: File(args[0]).absolute.path);
  try {
    await engine.load(File(args[1]).absolute.path);
    var fragments = 0;
    var finished = false;
    await for (final event in engine.chat([{'role': 'user', 'content': 'Once upon a time'}])) {
      if ((event['message'] as Map)['content'] != '') fragments++;
      if (event['done'] == true) finished = true;
    }
    if (fragments == 0 || !finished) throw StateError('No streamed inference result.');
    final measurement=await BenchmarkRunner().run(
      generate:()=>engine.chat([{'role':'user','content':BenchmarkRunner.prompt}],maxTokens:128,temperature:0),
      stop:engine.stop,metadata:{'engine':{'model':'CI tiny GGUF','acceleration':'CPU'}});
    if(measurement.tokens==null||measurement.tokens!<=0)throw StateError('Missing authoritative token usage');
    if(engine.cpuBackend==null)throw StateError('CPU backend was not identified');
    print('Measured real GGUF inference: ${measurement.tokens} tokens; backend ${engine.cpuBackend}');
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
