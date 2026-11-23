import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'native_text_engine.dart';
import '../settings/app_settings.dart';

class ModelRuntime {
  ModelRuntime({AppSettings? settings}):_preferences=settings ?? AppSettings.instance;
  final AppSettings _preferences;
  static final _native = NativeTextEngine();
  static Timer? _idle;
  Future<void> releaseMemory() async { _idle?.cancel(); await _native.unload(); }
  void _armIdle() {
    _idle?.cancel();
    final minutes = _preferences.get<int>('idleMinutes');
    if(minutes>0) _idle=Timer(Duration(minutes:minutes),()async{if(!_native.busy) {try {await _native.unload();}catch(_) {}}});
  }
  Future<void> suspend() async {
    stop();
    for(var i=0;i<20 && _native.busy;i++){await Future<void>.delayed(const Duration(milliseconds:100));}
    if(!_native.busy)await releaseMemory();
  }
  Future<void> preload() async {if(useLocal&&localPath.isNotEmpty){await _native.load(localPath);_armIdle();}}

  bool _cancelLocal = false;
  bool useLocal = false;
  String localPath = '';
  String get selectedName => useLocal ? File(localPath).uri.pathSegments.last : model;
  bool get ready => useLocal ? localPath.isNotEmpty : model.isNotEmpty && address.isNotEmpty;

  Future<void> selectLocal(String path) async {
    await _native.load(path);
    _armIdle();
    localPath = path;
    useLocal = true;
    await save();
  }

  Future<void> unloadLocal() async {
    await _native.unload();
    useLocal = false;
    localPath = '';
    await save();
  }

  String address = '';
  String model = '';
  HttpClient? _generation;

  Future<File> _settings() async => File(
    '${(await getApplicationSupportDirectory()).path}/runtime.json',
  );

  Future<void> load() async {
    final file = await _settings();
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    useLocal = data['useLocal'] as bool? ?? false;
    localPath = data['localPath'] as String? ?? '';
    if (useLocal && !await File(localPath).exists()) {
      useLocal = false;
      localPath = '';
    }
    address = data['address'] as String? ?? '';
    model = data['model'] as String? ?? '';
  }

  void configure(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Escribe una dirección HTTP o HTTPS válida.');
    }
    address = uri.toString().replaceFirst(RegExp(r'/$'), '');
  }

  Future<void> save() async {
    final file = await _settings();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode({'address': address, 'model': model, 'useLocal': useLocal, 'localPath': localPath}), flush: true);
    await temporary.rename(file.path);
  }

  Future<Map<String, dynamic>> request(String endpoint, {String method = 'GET',
      Map<String, dynamic>? body}) async {
    if(!_preferences.get<bool>('allowNetwork'))throw StateError('Acceso a red desactivado.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, Uri.parse('$address$endpoint'));
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final text = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 45));
      if (response.statusCode >= 400) throw HttpException('El motor devolvió ${response.statusCode}.');
      return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> models() async =>
      ((await request('/api/tags'))['models'] as List? ?? []).cast<Map<String, dynamic>>();

  Stream<Map<String, dynamic>> stream(String endpoint, Map<String, dynamic> body) async* {
    final settings = _preferences;
    body = {...body,'options':{...?body['options'] as Map<String,dynamic>?,
      'num_predict':settings.get<int>('maxTokens'),'temperature':settings.get<double>('temperature'),
      'num_ctx':settings.get<int>('context'),'num_thread':settings.get<int>('threads')}};
    if (endpoint == '/api/chat' && useLocal) {
      _idle?.cancel();
      _cancelLocal = false;
      await _native.load(localPath);
      if (_cancelLocal) return;
      try { yield* _native.chat((body['messages'] as List).cast<Map<String, dynamic>>()); } finally { _armIdle(); }
      return;
    }
    if(!_preferences.get<bool>('allowNetwork'))throw StateError('Acceso a red desactivado.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    _generation = client;
    try {
      final request = await client.postUrl(Uri.parse('$address$endpoint'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode >= 400) throw HttpException('El motor devolvió ${response.statusCode}.');
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())
          .timeout(const Duration(minutes: 3))) {
        if (line.trim().isEmpty) continue;
        final data = jsonDecode(line) as Map<String, dynamic>;
        if (data['error'] != null) throw StateError(data['error'].toString());
        yield data;
      }
    } finally {
      client.close(force: true);
      if (identical(_generation, client)) _generation = null;
    }
  }

  void stop() {
    _generation?.close(force: true);
    _cancelLocal = true;
    if (useLocal) _native.stop();
  }
}
