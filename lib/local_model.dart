import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

class LocalModel {
  LlamaController? _controller;
  bool _loaded = false;

  bool get supported => Platform.isAndroid;

  Future<File> _modelFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/qwen-local.gguf');
  }

  Future<bool> isInstalled() async => supported && await (await _modelFile()).exists();

  Future<void> install(String sourcePath) async {
    final source = File(sourcePath);
    final input = await source.open();
    try {
      final header = await input.read(4);
      if (String.fromCharCodes(header) != 'GGUF' || await input.length() < 1024) {
        throw const FormatException('Archivo GGUF inválido');
      }
    } finally {
      await input.close();
    }
    final target = await _modelFile();
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.part');
    try {
      await source.copy(temporary.path);
      await unload();
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> unload() async {
    final controller = _controller;
    _controller = null;
    _loaded = false;
    if (controller != null) await controller.dispose();
  }

  Stream<String> reply(List<ChatMessage> history) async* {
    final controller = _controller ??= LlamaController();
    if (!_loaded) {
      final model = await _modelFile();
      await controller.loadModel(
        modelPath: model.path,
        contextSize: 2048,
        threads: 4,
        gpuLayers: 0,
      );
      _loaded = true;
    }
    await controller.clearContext();
    yield* controller.generateChat(
      template: 'chatml',
      messages: [
        ChatMessage(role: 'system', content: 'Eres ZASKIA. Responde en el idioma del usuario. /no_think'),
        ...history,
      ],
      maxTokens: 384,
    );
  }
}
