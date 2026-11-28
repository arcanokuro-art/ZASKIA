import 'dart:convert';
import 'dart:io';
import '../settings/app_settings.dart';

class UpdateService {
  static const version = '0.15.0';
  static const releases = 'https://github.com/arcanokuro-art/ZASKIA/releases';
  static Future<Map<String,dynamic>?> check() async {
    if(!AppSettings.instance.get<bool>('allowNetwork')) throw StateError('Acceso a red desactivado.');
    final client=HttpClient()..connectionTimeout=const Duration(seconds:10);
    try {
      final request=await client.getUrl(Uri.https('api.github.com','/repos/arcanokuro-art/ZASKIA/releases',{'per_page':'20'}));
      request.headers.set(HttpHeaders.userAgentHeader,'ZASKIA/$version');
      final response=await request.close().timeout(const Duration(seconds:30));
      if(response.statusCode!=200) throw HttpException('GitHub ${response.statusCode}');
      final entries=jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds:30))) as List;
      final suffix=Platform.isLinux?'-linux-amd64.deb':'.apk';
      for(final raw in entries) {
        final release=raw as Map<String,dynamic>;
        if(release['draft']==true) continue;
        final tag=(release['tag_name'] as String).replaceFirst(RegExp(r'^v'),'');
        if(!newer(tag,version)) continue;
        final asset=(release['assets'] as List).cast<Map<String,dynamic>>().where((a)=>(a['name'] as String).endsWith(suffix)).firstOrNull;
        if(asset!=null) return {'version':tag,'url':asset['browser_download_url']};
      }
      return null;
    } finally {client.close(force:true);}
  }
  static bool newer(String a,String b) {
    if(!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(a)) return false;
    final x=a.split('.').map(int.parse).toList(), y=b.split('.').map(int.parse).toList();
    for(var i=0;i<3;i++) { if(x[i]!=y[i]) return x[i]>y[i]; }
    return false;
  }
}
