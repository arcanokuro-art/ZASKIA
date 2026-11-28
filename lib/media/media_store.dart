import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MediaStore {
  MediaStore({this.directory});
  final Directory? directory;
  Future<Directory> root()async=> (directory ?? Directory('${(await getApplicationSupportDirectory()).path}/media')).create(recursive:true);
  Future<Directory> create(String kind,String prompt)async{
    final d=await (await root()).createTemp('job-');
    await record(d,{'kind':kind,'prompt':prompt,'created':DateTime.now().millisecondsSinceEpoch,'status':'Procesando en el motor','files':<String>[]});return d;
  }
  Future<void> record(Directory job,Map<String,dynamic> data)async{
    final tmp=File('${job.path}/job.json.tmp');await tmp.writeAsString(jsonEncode(data),flush:true);await tmp.rename('${job.path}/job.json');
  }
  Future<Map<String,dynamic>> read(Directory job)async=>Map<String,dynamic>.from(jsonDecode(await File('${job.path}/job.json').readAsString()) as Map);
  Future<List<Map<String,dynamic>>> list()async{
    final result=<Map<String,dynamic>>[];
    await for(final e in (await root()).list()){
      if(e is! Directory)continue;
      try{final data=await read(e);result.add({...data,'directory':e.path});}catch(_){}
    }
    result.sort((a,b)=>(b['created'] as int).compareTo(a['created'] as int));return result;
  }
}
