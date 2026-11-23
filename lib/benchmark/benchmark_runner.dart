import 'dart:async';
import 'benchmark_result.dart';

class BenchmarkCancelled implements Exception {}

/// Measures delivered text separately from authoritative backend token counts.
class BenchmarkRunner {
  static const protocol='zaskia-text-128-v1';
  static const prompt='Write a numbered list of simple everyday objects, from 1 to 80. Use one short item per line. Do not add an introduction.';
  bool running=false,cancelled=false;
  void Function()? _stop;
  void cancel(){cancelled=true;_stop?.call();}

  Future<BenchmarkResult> run({required Stream<Map<String,dynamic>> Function() generate,
      required void Function() stop,required Map<String,dynamic> metadata,
      Duration timeout=const Duration(minutes:2)})async {
    if(running)throw StateError('Benchmark busy');
    running=true;cancelled=false;_stop=stop;
    final watch=Stopwatch()..start();
    double? first;
    int? tokens;
    double? reportedRate;
    var finished=false,timedOut=false;
    final deadline=Timer(timeout,(){timedOut=true;stop();});
    // Keep at most the small test response, and do not persist it.
    final response=StringBuffer();
    try {
      await for(final event in generate().timeout(timeout)) {
        if(timedOut)throw TimeoutException('Benchmark deadline');
        if(cancelled)throw BenchmarkCancelled();
        final content=event['message']?['content'] as String? ?? '';
        if(content.isNotEmpty) {
          first??=watch.elapsedMicroseconds/1000000;
          response.write(content);
          if(response.length>262144)throw StateError('Benchmark output limit');
        }
        if(event['eval_count'] is int && (event['eval_count'] as int)>0)tokens=event['eval_count'] as int;
        final duration=event['eval_duration'];
        if(tokens!=null && duration is num && duration>0)reportedRate=tokens*1000000000/duration;
        if(event['done']==true)finished=true;
      }
      if(timedOut)throw TimeoutException('Benchmark deadline');
      if(cancelled)throw BenchmarkCancelled();
      watch.stop();
      if(!finished || (response.isEmpty && tokens==null))throw StateError('Incomplete benchmark');
      final total=(watch.elapsedMicroseconds==0?1:watch.elapsedMicroseconds)/1000000;
      final count=response.toString().runes.length;
      return BenchmarkResult({...metadata,'schema':1,'id':'${DateTime.now().microsecondsSinceEpoch}',
        'createdAt':DateTime.now().toUtc().toIso8601String(),'protocol':protocol,
        'requestedMaxTokens':128,'temperature':0.0,'generatedCharacters':count,
        'totalSeconds':total,'firstTextSeconds':first,'charactersPerSecond':count/total,
        'completionTokens':tokens,'endToEndTokensPerSecond':tokens==null?null:tokens/total,
        'backendTokensPerSecond':reportedRate});
    }catch(_) {stop();rethrow;}
    finally{deadline.cancel();watch.stop();running=false;_stop=null;}
  }
}
