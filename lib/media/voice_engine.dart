import 'dart:convert';
import 'dart:io';
import 'engine_http.dart';

class VoiceEngine {
  VoiceEngine(this.http);
  final EngineHttp http;
  Future<List<String>> models()async{
    final data=await http.json('GET','/v1/models') as Map;
    return (data['data'] as List? ?? []).map((m)=>(m as Map)['id'] as String).toList();
  }
  Future<File> speak(String text,String model,String voice,File destination)async{
    if(text.trim().isEmpty||model.trim().isEmpty)throw const FormatException('Indica texto y modelo de voz.');
    final r=await http.open('POST','/v1/audio/speech',json:{'input':text,'model':model,'voice':voice,'response_format':'wav'});
    if(r.headers.contentType?.mimeType=='application/json')throw const FormatException('El motor no devolvió audio.');
    return http.save(r,destination);
  }
  Future<String> transcribe(File file,String model)async{
    if(model.trim().isEmpty)throw const FormatException('Indica el modelo de transcripción.');
    final boundary='Zaskia${DateTime.now().microsecondsSinceEpoch}';
    final r=await http.open('POST','/v1/audio/transcriptions',contentType:'multipart/form-data; boundary=$boundary',
      body:http.multipart(boundary,{'model':model,'response_format':'json'},'file',file));
    final data=jsonDecode(await utf8.decoder.bind(r).join().timeout(const Duration(minutes:5))) as Map;
    if(data['text'] is! String)throw const FormatException('La respuesta no contiene una transcripción.');
    return data['text'] as String;
  }
}
