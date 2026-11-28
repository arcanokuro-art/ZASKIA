import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A request scope shared by one job; cancelling closes only this client's I/O.
class EngineHttp {
  EngineHttp(String address,{this.allowed=true}) : base=validateAddress(address);
  final Uri base;
  final bool allowed;
  final _client=HttpClient()..connectionTimeout=const Duration(seconds:15);
  bool cancelled=false;
  static Uri validateAddress(String text) {
    final u=Uri.tryParse(text.trim());
    if(u==null||!['http','https'].contains(u.scheme)||u.host.isEmpty||u.userInfo.isNotEmpty||u.hasQuery||u.hasFragment)throw const FormatException('Dirección del motor no válida.');
    return u.replace(path:u.path.replaceFirst(RegExp(r'/$'),''));
  }
  Uri uri(String path,{Map<String,String>? query})=>base.replace(path:'${base.path}$path',queryParameters:query);
  Future<HttpClientResponse> open(String method,String path,{Object? json,Map<String,String>? query, String? contentType,Stream<List<int>>? body})async{
    if(!allowed)throw StateError('Acceso a red desactivado.');
    if(cancelled)throw StateError('Operación cancelada.');
    final r=await _client.openUrl(method,uri(path,query:query));
    if(json!=null){r.headers.contentType=ContentType.json;r.write(jsonEncode(json));}
    if(contentType!=null)r.headers.set(HttpHeaders.contentTypeHeader,contentType);
    if(body!=null)await r.addStream(body);
    final response=await r.close().timeout(const Duration(minutes:5));
    if(response.statusCode<200||response.statusCode>=300){
      await response.drain<void>();throw HttpException('El motor devolvió HTTP ${response.statusCode}.');
    }
    return response;
  }
  Future<dynamic> json(String method,String path,{Object? body})async{
    final response=await open(method,path,json:body);
    final bytes=<int>[];
    await for(final c in response.timeout(const Duration(seconds:45))){bytes.addAll(c);if(bytes.length>16*1024*1024)throw const FormatException('Respuesta demasiado grande.');}
    return bytes.isEmpty?<String,dynamic>{}:jsonDecode(utf8.decode(bytes));
  }
  Future<File> save(HttpClientResponse response,File target)async{
    final partial=File('${target.path}.part');await target.parent.create(recursive:true);
    final sink=partial.openWrite();var count=0;
    try{
      await for(final c in response.timeout(const Duration(minutes:2))){if(cancelled)throw StateError('Operación cancelada.');sink.add(c);count+=c.length;}
      await sink.close();
      if(count==0||(response.contentLength>=0&&count!=response.contentLength))throw const FormatException('Archivo incompleto.');
      if(cancelled)throw StateError('Operación cancelada.');
      return await partial.rename(target.path);
    }catch(_){try{await sink.close();}catch(_){}if(await partial.exists())await partial.delete();rethrow;}
  }
  Stream<List<int>> multipart(String boundary,Map<String,String> fields,String key,File file)async*{
    for(final e in fields.entries){yield utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="${e.key}"\r\n\r\n${e.value}\r\n');}
    final ext=file.path.split('.').last.toLowerCase();
    final suffix=RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)?ext:'bin';
    yield utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="$key"; filename="input.$suffix"\r\nContent-Type: application/octet-stream\r\n\r\n');
    yield* file.openRead();yield utf8.encode('\r\n--$boundary--\r\n');
  }
  void cancel(){cancelled=true;_client.close(force:true);}
  void close(){_client.close(force:true);}
}
