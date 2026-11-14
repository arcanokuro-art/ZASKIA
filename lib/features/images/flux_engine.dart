import 'dart:io';
import 'dart:typed_data' show Endian;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum FluxWeight {
  diffusion('FLUX.2 klein 4B', 'diffusion.gguf'),
  encoder('Codificador Qwen3 4B', 'encoder.gguf'),
  vae('VAE de FLUX.2', 'vae.safetensors');

  const FluxWeight(this.label, this.filename);
  final String label;
  final String filename;
}

class FluxEngine {
  static const _platform = MethodChannel('zaskia/flux');

  Future<Directory> _weights() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/flux');
  }

  Future<Set<FluxWeight>> installed() async {
    if (!Platform.isAndroid) return {};
    final dir = await _weights();
    return {
      for (final weight in FluxWeight.values)
        if (await File('${dir.path}/${weight.filename}').exists()) weight,
    };
  }

  Future<void> install(FluxWeight weight, String sourcePath) async {
    final source = File(sourcePath);
    final input = await source.open();
    try {
      final header = await input.read(8);
      final size = await input.length();
      if (header.length != 8 || size < 1024 ||
          (weight != FluxWeight.vae && String.fromCharCodes(header.take(4)) != 'GGUF')) {
        throw const FormatException('Formato de pesos inválido.');
      }
      if (weight == FluxWeight.vae) {
        final length = ByteData.sublistView(header).getUint64(0, Endian.little);
        if (length < 2 || length > 100000000 || length > size - 8 ||
            (await input.readByte()) != 123) {
          throw const FormatException('Formato safetensors inválido.');
        }
      }
    } finally {
      await input.close();
    }
    final dir = await _weights();
    await dir.create(recursive: true);
    final target = '${dir.path}/${weight.filename}';
    final partial = File('$target.part');
    try {
      await source.copy(partial.path);
      await partial.rename(target);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<File> generate(String prompt, List<String> references) async {
    final dir = await _weights();
    final cache = await getTemporaryDirectory();
    final job = await cache.createTemp('flux-');
    try {
      final refs = [
        for (final (index, path) in references.indexed)
          await _prepareReference(path, '${job.path}/reference-$index.png'),
      ];
      final resultPath = '${job.path}/result.png';
      await _platform.invokeMethod<void>('generate', {
        'args': [
          '--diffusion-model', '${dir.path}/${FluxWeight.diffusion.filename}',
          '--llm', '${dir.path}/${FluxWeight.encoder.filename}',
          '--vae', '${dir.path}/${FluxWeight.vae.filename}',
          '--prompt', prompt, '--output', resultPath,
          '--width', '512', '--height', '512', '--steps', '4',
          '--cfg-scale', '1.0', '--sampling-method', 'euler',
          '--threads', '4', '--mmap', '--vae-tiling',
          for (final ref in refs) ...['--ref-image', ref],
        ],
        'output': resultPath,
      });
      final support = await getApplicationSupportDirectory();
      final results = Directory('${support.path}/images');
      await results.create(recursive: true);
      return await File(resultPath).rename('${results.path}/${job.uri.pathSegments.where((part) => part.isNotEmpty).last}.png');
    } finally {
      await job.delete(recursive: true);
    }
  }

  Future<String> _prepareReference(String path, String output) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final longest = width > height ? width : height;
        if (longest <= 512) return ui.TargetImageSize();
        return width >= height
          ? ui.TargetImageSize(width: 512)
          : ui.TargetImageSize(height: 512);
      },
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw const FormatException('Imagen de referencia inválida.');
        await File(output).writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
        return output;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
