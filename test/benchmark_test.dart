import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/benchmark/benchmark_runner.dart';
import 'package:zaskia/benchmark/benchmark_store.dart';

void main(){
  Stream<Map<String,dynamic>> sample({bool tokens=true})async* {
    yield {'message':{'content':'Hola '}};
    await Future<void>.delayed(const Duration(milliseconds:2));
    yield {'message':{'content':'😀'}};
    yield {'done':true,if(tokens)'eval_count':7,if(tokens)'eval_duration':70000000};
  }
  test('stream fragments are not tokens and saved reports exclude generated content',()async{
    final runner=BenchmarkRunner();
    final result=await runner.run(generate:()=>sample(),stop:(){},metadata:{'engine':{'model':'test','location':'local'}});
    expect(result.characters,6);expect(result.tokens,7);
    expect(result.data['backendTokensPerSecond'],100);
    expect(result.totalSeconds,greaterThan(0));
    final noTokens=await runner.run(generate:()=>sample(tokens:false),stop:(){},metadata:{});
    expect(noTokens.tokens,isNull);expect(noTokens.data['endToEndTokensPerSecond'],isNull);
    final root=await Directory.systemTemp.createTemp('zaskia-benchmark-');
    addTearDown(()=>root.delete(recursive:true));
    final store=BenchmarkStore(file:File('${root.path}/results.json'));
    await store.save(result);expect((await store.list()).single.tokens,7);
    final path='${root.path}/export.json';await store.export(path,await store.list());
    final data=await File(path).readAsString();expect(data, isNot(contains('Hola')));
    expect(jsonDecode(data)['format'],'ZASKIA-benchmarks-1');
  });
  test('cancelled and incomplete tests cannot be stored as valid measurements',()async{
    final runner=BenchmarkRunner();var stopped=false;
    Stream<Map<String,dynamic>> interrupted()async*{
      yield {'message':{'content':'partial'}};runner.cancel();yield {'done':true};
    }
    await expectLater(runner.run(generate:interrupted,stop:(){stopped=true;},metadata:{}),throwsA(isA<BenchmarkCancelled>()));
    expect(stopped,true);expect(runner.running,false);
    await expectLater(runner.run(generate:()=>Stream.value({'message':{'content':'partial'}}),stop:(){},metadata:{}),throwsStateError);
  });
  test('deadline stops a silent backend and concurrent tests are rejected',()async{
    final runner=BenchmarkRunner();final source=StreamController<Map<String,dynamic>>();
    var stopped=false;
    final future=runner.run(generate:()=>source.stream,stop:(){stopped=true;},metadata:{},timeout:const Duration(milliseconds:20));
    await expectLater(runner.run(generate:()=>sample(),stop:(){},metadata:{}),throwsStateError);
    await expectLater(future,throwsA(isA<TimeoutException>()));
    expect(stopped,true);await source.close();expect(runner.running,false);
  });
}
