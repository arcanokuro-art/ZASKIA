import 'dart:convert';

class ChatContext {
  const ChatContext(this.messages,this.omittedTurns);
  final List<Map<String,String>> messages;
  final int omittedTurns;
  // Deliberately conservative estimate. Model tokenizers are not interchangeable.
  static int cost(String text)=>(utf8.encode(text).length/2).ceil()+16;
  static ChatContext build({required String system,required List<Map<String,String>> turns,required int context,required int maxTokens,required int maxTurns}){
    final budget=context-maxTokens.clamp(1,context~/2)-64;
    var used=system.isEmpty?0:cost(system);
    final selected=<Map<String,String>>[];
    var included=0;
    for(final turn in turns.reversed.take(maxTurns)){
      final size=cost(turn['user']??'')+((turn['assistant']??'').isEmpty?0:cost(turn['assistant']!));
      if(used+size>budget){
        if(included==0)throw const FormatException('El mensaje y las instrucciones exceden el contexto. Reduce el texto o aumenta el contexto.');
        break;
      }
      used+=size;included++;
      selected.insertAll(0,[{'role':'user','content':turn['user']??''},if((turn['assistant']??'').isNotEmpty){'role':'assistant','content':turn['assistant']!}]);
    }
    return ChatContext([if(system.isNotEmpty){'role':'system','content':system},...selected],turns.length-included);
  }
}

class ConversationExport {
  static String markdown(String name,List<Map<String,dynamic>> messages)=>'# $name\n\n${messages.map((m)=>'## Usuario\n\n${m['text']}\n\n## ZASKIA\n\n${m['answer']??''}\n').join('\n')}';
  static List<Map<String,dynamic>> parse(String text){
    final data=jsonDecode(text);
    final messages=data is Map?data['messages']:null;
    if(messages is! List||messages.length>10000)throw const FormatException('Conversación JSON no válida.');
    return messages.map((m){if(m is! Map||m['text'] is! String||m['answer'] is! String)throw const FormatException('Mensaje no válido.');
      // Imports never read arbitrary filesystem paths contained in a JSON file.
      return <String,dynamic>{'text':m['text'],'answer':m['answer'],'attachments':<dynamic>[],'mode':'chat','note':'',
        'status':m['status'] is String?m['status']:'imported'};}).toList();
  }
}
