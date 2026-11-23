import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'benchmark_result.dart';

class BenchmarkStore {
  BenchmarkStore({this.file});
  final File? file;
  Future<File> _file()async=>file??File('${(await getApplicationSupportDirectory()).path}/benchmarks.json');
  Future<List<BenchmarkResult>> list()async{
    final f=await _file();if(!await f.exists())return [];
    final data=jsonDecode(await f.readAsString()) as List;
    return data.cast<Map<String,dynamic>>().map(BenchmarkResult.fromJson).toList();
  }
  Future<void> save(BenchmarkResult result)async{
    final items=[result,...await list()].take(50).map((r)=>r.toJson()).toList();
    final f=await _file();await f.parent.create(recursive:true);
    final temp=File('${f.path}.tmp');await temp.writeAsString(jsonEncode(items),flush:true);await temp.rename(f.path);
  }
  Future<void> export(String path,List<BenchmarkResult> results)async{
    final f=File(path);final temp=File('$path.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'format':'ZASKIA-benchmarks-1','results':results.map((r)=>r.toJson()).toList(),
    }),flush:true);await temp.rename(f.path);
  }
}
