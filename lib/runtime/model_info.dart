import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class ModelInfo {
  const ModelInfo({
    required this.path, required this.bytes, required this.format,
    required this.capabilities, required this.engine, required this.metadata,
  });

  final String path;
  final int bytes;
  final String format;
  final String capabilities;
  final String engine;
  final Map<String, String> metadata;

  static Future<ModelInfo> inspect(File file) async {
    final bytes = await file.length();
    final metadata = <String, String>{};
    var format = 'Archivo GGUF sin verificar';
    var capabilities = 'Por comprobar';
    var engine = 'Compatibilidad por comprobar';
    RandomAccessFile? input;
    try {
      input = await file.open();
      final reader = _GgufReader(input, bytes);
      if (String.fromCharCodes(await reader.read(4)) != 'GGUF') {
        throw const FormatException('Cabecera inválida');
      }
      final version = await reader.number(4);
      if (version != 2 && version != 3) throw const FormatException('Versión no soportada');
      format = 'GGUF v$version';
      final tensors = await reader.number(8);
      final count = await reader.number(8);
      if (count > 100000) throw const FormatException('Metadatos excesivos');
      metadata['Tensores'] = '$tensors';
      const fields = {
        'general.name': 'Nombre del modelo',
        'general.architecture': 'Arquitectura',
        'general.size_label': 'Tamaño del modelo',
        'general.finetune': 'Ajuste',
        'general.file_type': 'Tipo de cuantización GGUF',
        'general.license': 'Licencia',
        'split.count': 'Número de partes',
      };
      for (var i = 0; i < count; i++) {
        final key = await reader.string(keep: true);
        final type = await reader.number(4);
        final value = await reader.value(type, keep: fields.containsKey(key));
        if (fields[key] != null && value != null) metadata[fields[key]!] = value;
      }
      final architecture = metadata['Arquitectura'];
      const textArchitectures = {
        'llama', 'qwen2', 'qwen3', 'qwen3moe', 'gemma', 'gemma2', 'gemma3',
        'phi2', 'phi3', 'mistral', 'gpt2', 'gptneox', 'falcon', 'starcoder',
        'starcoder2', 'deepseek', 'deepseek2', 'bert', 'nomic-bert',
      };
      if (architecture == 'bert' || architecture == 'nomic-bert') {
        capabilities = 'Embeddings · requiere un motor de embeddings';
        engine = 'El chat local no ejecuta embeddings';
      } else if (textArchitectures.contains(architecture)) {
        capabilities = 'Texto · arquitectura reconocida';
        engine = 'llama.cpp · verificar cargando el modelo';
      }
      if (int.tryParse(metadata['Número de partes'] ?? '1') != 1 ||
          RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false).hasMatch(file.path)) {
        engine = 'Modelo dividido · carga pendiente de soporte';
      }
    } on Exception {
      metadata['Lectura'] = 'Metadatos incompletos o no reconocidos';
    } finally {
      await input?.close();
    }
    return ModelInfo(path: file.path, bytes: bytes, format: format,
      capabilities: capabilities, engine: engine, metadata: metadata);
  }

  String get size => bytes >= 1000000000
    ? '${(bytes / 1000000000).toStringAsFixed(2)} GB'
    : '${(bytes / 1000000).toStringAsFixed(1)} MB';
}

class _GgufReader {
  _GgufReader(this.file, this.length);
  final RandomAccessFile file;
  final int length;
  int operations = 0;

  Future<Uint8List> read(int count) async {
    final position = await file.position();
    if (++operations > 2000000 || count < 0 || count > 4000000 ||
        position + count > length || position + count > 32000000) {
      throw const FormatException('Límite de metadatos');
    }
    final bytes = await file.read(count);
    if (bytes.length != count) throw const FormatException('Archivo truncado');
    return bytes;
  }

  Future<int> number(int width) async {
    final bytes = ByteData.sublistView(await read(width));
    return switch (width) {
      1 => bytes.getUint8(0),
      2 => bytes.getUint16(0, Endian.little),
      4 => bytes.getUint32(0, Endian.little),
      8 => bytes.getUint64(0, Endian.little),
      _ => throw const FormatException('Tipo desconocido'),
    };
  }

  Future<void> skip(int count) async {
    final next = await file.position() + count;
    if (++operations > 2000000 || count < 0 || next > length || next > 32000000) {
      throw const FormatException('Límite de metadatos');
    }
    await file.setPosition(next);
  }

  Future<String> string({required bool keep}) async {
    final size = await number(8);
    if (keep) {
      final bytes = await read(size);
      return utf8.decode(bytes);
    }
    await skip(size);
    return '';
  }

  Future<String?> value(int type, {required bool keep}) async {
    if (type == 8) return string(keep: keep);
    if (type == 9) {
      final subtype = await number(4);
      final count = await number(8);
      if (subtype == 9 || count > 1000000) throw const FormatException('Arreglo inválido');
      const sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8};
      if (sizes.containsKey(subtype)) {
        await skip(count * sizes[subtype]!);
      } else if (subtype == 8) {
        for (var i = 0; i < count; i++) {
          await string(keep: false);
        }
      } else {
        throw const FormatException('Tipo desconocido');
      }
      return null;
    }
    const widths = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8};
    final width = widths[type];
    if (width == null) throw const FormatException('Tipo desconocido');
    if (!keep) {
      await skip(width);
      return null;
    }
    return '${await number(width)}';
  }
}
