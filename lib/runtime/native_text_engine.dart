import 'dart:io';

import 'linux_text_engine.dart';

import 'package:llama_flutter_android/llama_flutter_android.dart';

class NativeTextEngine {
  final _linux = LinuxTextEngine();
  LlamaController? _controller;
  String? _androidPath;
  String? get loadedPath => Platform.isLinux ? _linux.loadedPath : _androidPath;
  bool busy = false;
  String _config = '';
  int _threads=4,_context=2048;
  String? get cpuBackend=>Platform.isLinux?_linux.cpuBackend:null;
  bool _cancelled = false;
  bool matches(String path,{required int threads,required int contextSize})=>loadedPath==path&&_config=='$threads:$contextSize';

  Future<void> load(String path,{int threads=4,int contextSize=2048}) async {
    if (busy) throw StateError('Espera a que termine la generación.');
    final config = '$threads:$contextSize';
    if (loadedPath == path && _config == config) return;
    await unload();
    _config = config;_threads=threads;_context=contextSize;
    if (Platform.isLinux) return _linux.load(path,threads:_threads,contextSize:_context);
    final file = await File(path).open();
    try {
      if (String.fromCharCodes(await file.read(4)) != 'GGUF') {
        throw const FormatException('El archivo no es un GGUF válido.');
      }
    } finally {
      await file.close();
    }
    await unload();
    final controller = LlamaController();
    _controller = controller;
    try {
      await controller.loadModel(modelPath: path, contextSize: _context, threads: _threads, gpuLayers: 0);
      _androidPath = path;
    } catch (_) {
      await unload();
      rethrow;
    }
  }

  Future<void> unload() async {
    if (busy) throw StateError('Espera a que termine la generación.');
    if (Platform.isLinux) return _linux.unload();
    final controller = _controller;
    _controller = null;
    _androidPath = null;
    if (controller != null) await controller.dispose();
  }

  Stream<Map<String, dynamic>> chat(List<Map<String, dynamic>> messages,{int maxTokens=512,double temperature=0.7}) async* {
    if (busy) throw StateError('El motor ya está generando.');
    if (Platform.isLinux) {
      busy = true;
      try { yield* _linux.chat(messages,maxTokens:maxTokens.clamp(1,_context ~/ 2).toInt(),temperature:temperature); } finally { busy = false; }
      return;
    }
    final controller = _controller;
    if (controller == null) throw StateError('Carga un modelo local primero.');
    busy = true;
    _cancelled = false;
    try {
      await controller.clearContext();
      if (_cancelled) return;
      await for (final token in controller.generateChat(
        messages: messages.map((item) => ChatMessage(
          role: item['role'] as String, content: item['content'] as String,
        )).toList(),
        maxTokens: maxTokens.clamp(1,_context ~/ 2).toInt(),
        temperature: temperature,
      )) {
        if (_cancelled) break;
        yield {'message': {'content': token}, 'done': false};
      }
      yield {'message': {'content': ''}, 'done': true};
    } finally {
      busy = false;
    }
  }

  Future<void> stop() async {
    if (Platform.isLinux) { _linux.stop(); return; }
    _cancelled = true;
    await _controller?.stop();
  }
}
