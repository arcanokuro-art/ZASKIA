import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';

class NativeTextEngine {
  LlamaController? _controller;
  String? loadedPath;
  bool busy = false;
  bool _cancelled = false;

  Future<void> load(String path) async {
    if (busy) throw StateError('Espera a que termine la generación.');
    if (loadedPath == path) return;
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
      await controller.loadModel(modelPath: path, contextSize: 2048, threads: 4, gpuLayers: 0);
      loadedPath = path;
    } catch (_) {
      await unload();
      rethrow;
    }
  }

  Future<void> unload() async {
    if (busy) throw StateError('Espera a que termine la generación.');
    final controller = _controller;
    _controller = null;
    loadedPath = null;
    if (controller != null) await controller.dispose();
  }

  Stream<Map<String, dynamic>> chat(List<Map<String, dynamic>> messages) async* {
    if (busy) throw StateError('El motor ya está generando.');
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
        maxTokens: 512,
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
    _cancelled = true;
    await _controller?.stop();
  }
}
