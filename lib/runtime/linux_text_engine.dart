import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Private, CPU-only llama.cpp process shipped alongside the Linux application.
class LinuxTextEngine {
  LinuxTextEngine({String? executable}) : _executable = executable ??
      '${File(Platform.resolvedExecutable).parent.path}/zaskia-engine';
  final String _executable;
  Process? _process;
  int? _exitCode;
  String? loadedPath;
  String? cpuBackend;
  bool _abortLoad=false;
  int _port = 0;
  String _key = '';
  String _diagnostic = '';
  HttpClient? _generation;
  bool _cancelled = false;
  bool _busy = false;
  bool _loading = false;

  Future<void> load(String path, {int threads = 4,int contextSize = 2048}) async {
    if (_loading || _busy) throw StateError('Espera a que termine el motor.');
    if (loadedPath == path && _process != null && _exitCode == null) return;
    final file = await File(path).open();
    try {
      if (String.fromCharCodes(await file.read(4)) != 'GGUF') {
        throw const FormatException('El archivo no es un GGUF válido.');
      }
    } finally {
      await file.close();
    }
    await unload();
    _loading = true;_abortLoad=false;cpuBackend=null;
    try {
      if (!await File(_executable).exists()) {
        throw StateError('Falta el motor Linux. Reinstala el paquete .deb de ZASKIA.');
      }
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _port = socket.port;
      await socket.close();
      _key = List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _exitCode = null;
      _diagnostic = '';
      final process = await Process.start(_executable, [
        '--model', path, '--host', '127.0.0.1', '--port', '$_port',
        '--ctx-size', '$contextSize', '--parallel', '1', '--n-gpu-layers', '0',
        '--threads', '${max(1, min(threads, Platform.numberOfProcessors))}',
        '--no-webui',
      ], environment: {'LLAMA_API_KEY': _key},workingDirectory:File(_executable).parent.path);
      _process = process;
      void log(List<int> bytes) {
        _diagnostic += utf8.decode(bytes, allowMalformed: true);
        final match=RegExp(r'loaded CPU backend from .*?(libggml-cpu[^/\s]*\.so)').firstMatch(_diagnostic);
        if(match!=null)cpuBackend=match[1];
        if (_diagnostic.length > 4000) _diagnostic = _diagnostic.substring(_diagnostic.length - 4000);
      }
      process.stdout.listen(log);
      process.stderr.listen(log);
      unawaited(process.exitCode.then((code) {
        if (identical(_process, process)) { _exitCode = code; loadedPath = null; cpuBackend=null; }
      }));
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        if(_abortLoad)throw StateError('Carga cancelada.');
        if (_exitCode != null) throw StateError('El motor no pudo cargar el modelo (código $_exitCode). $_diagnostic');
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
        try {
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:$_port/health'));
          final response = await request.close().timeout(const Duration(seconds: 2));
          await response.drain<void>();
          if (response.statusCode == 200) {
            // Read the actual loaded library: startup logging can be suppressed.
            try {
              final maps = await File('/proc/${process.pid}/maps').readAsString();
              cpuBackend = RegExp(r'libggml-cpu[^/\s]*\.so').firstMatch(maps)?.group(0) ?? cpuBackend;
            } on FileSystemException { /* Keep the backend reported by stderr. */ }
            loadedPath = path;
            return;
          }
        } on IOException {
          // The process is still starting or loading the model.
        } on TimeoutException {
          // Keep waiting within the overall model load deadline.
        } finally {
          client.close(force: true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw TimeoutException('El modelo tardó más de cinco minutos en cargar.');
    } catch (_) {
      await _shutdown();
      rethrow;
    } finally {
      _loading = false;
    }
  }

  Future<void> unload() async {
    if (_loading || _busy) throw StateError('Espera a que termine el motor.');
    await _shutdown();
  }

  Future<void> _shutdown() async {
    stop();
    final process = _process;
    _process = null;
    loadedPath = null;cpuBackend=null;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  Stream<Map<String, dynamic>> chat(List<Map<String, dynamic>> messages,{int maxTokens = 512,double temperature = 0.7}) async* {
    if (_busy || _loading) throw StateError('El motor está ocupado.');
    if (loadedPath == null || _exitCode != null) throw StateError('Carga un modelo local primero.');
    _busy = true;
    _cancelled = false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    _generation = client;
    try {
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_key');
      request.write(jsonEncode({'messages': messages, 'stream': true, 'max_tokens': maxTokens,'temperature':temperature,'stream_options':{'include_usage':true}}));
      final response = await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        final error = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 10));
        throw HttpException('El modelo devolvió ${response.statusCode}: $error');
      }
      int? tokens;double? duration;
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())
          .timeout(const Duration(minutes: 3))) {
        if (_cancelled) break;
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        final data = jsonDecode(payload) as Map<String, dynamic>;
        if (data['error'] != null) throw StateError(data['error'].toString());
        final usage=data['usage'] as Map?;
        if(usage?['completion_tokens'] is int)tokens=usage!['completion_tokens'] as int;
        final timings=data['timings'] as Map?;
        if(timings?['predicted_ms'] is num)duration=(timings!['predicted_ms'] as num).toDouble()*1000000;
        final choices = data['choices'] as List? ?? [];
        if (choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'] as Map? ?? {};
        final text = delta['content'] as String? ?? '';
        if (text.isNotEmpty) yield {'message': {'content': text}, 'done': false};
      }
      if (!_cancelled) yield {'message': {'content': ''}, 'done': true,
        if(tokens!=null)'eval_count':tokens,if(duration!=null)'eval_duration':duration};
    } on IOException {
      if (!_cancelled) rethrow;
    } finally {
      client.close(force: true);
      if (identical(_generation, client)) _generation = null;
      _busy = false;
    }
  }

  void stop() {
    _cancelled = true;
    if(_loading){_abortLoad=true;_process?.kill();}
    _generation?.close(force: true);
  }
}
