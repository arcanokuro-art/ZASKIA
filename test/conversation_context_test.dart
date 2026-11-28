import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/chat/context_builder.dart';
void main(){
  test('context preserves system and most recent complete turns',(){
    final c=ChatContext.build(system:'habla español',turns:[{'user':'old'*100,'assistant':'a'*100},{'user':'nuevo','assistant':''}],context:512,maxTokens:128,maxTurns:20);
    expect(c.omittedTurns,1);expect(c.messages.first['role'],'system');expect(c.messages.last['content'],'nuevo');
  });
  test('latest oversized prompt is rejected instead of silently truncated',(){
    expect(()=>ChatContext.build(system:'',turns:[{'user':'文'*1000}],context:512,maxTokens:128,maxTurns:20),throwsFormatException);
  });
  test('JSON imports strip attachment paths and markdown includes both sides',(){
    final m=ConversationExport.parse('{"messages":[{"text":"hola","answer":"mundo","attachments":[{"path":"/etc/passwd"}]}]}');
    expect(m.single['attachments'],isEmpty);expect(ConversationExport.markdown('chat',m),contains('mundo'));
  });
}
