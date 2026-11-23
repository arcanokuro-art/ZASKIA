import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class HuggingFaceScreen extends StatefulWidget {
  const HuggingFaceScreen({super.key});
  @override
  State<HuggingFaceScreen> createState() => _HuggingFaceScreenState();
}

class _HuggingFaceScreenState extends State<HuggingFaceScreen> {
  final _search = TextEditingController();
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  List<Map<String, dynamic>> _results = [];
  bool _busy = false;
  String _status = 'Busca repositorios públicos por nombre.';
  HttpClient? _download;

  @override
  void dispose() {
    _client.close(force: true);
    _download?.close(force: true);
    _search.dispose();
    super.dispose();
  }

  Future<dynamic> _json(Uri uri) async {
    final request = await _client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw HttpException('Respuesta ${response.statusCode}');
    return jsonDecode(await response.transform(utf8.decoder).join()
      .timeout(const Duration(seconds: 30)));
  }

  Future<void> _find() async {
    if (_busy || _search.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = await _json(Uri.https('huggingface.co', '/api/models', {
        'search': _search.text.trim(), 'limit': '25', 'sort': 'downloads', 'direction': '-1',
      })) as List;
      if (mounted) setState(() {
        _results = data.cast<Map<String, dynamic>>();
        _status = '${data.length} resultados · catálogo de Hugging Face';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'No se pudo consultar Hugging Face. Reintenta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _files(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final detail = await _json(Uri.https('huggingface.co', '/api/models/$id', {'blobs': 'true'}))
          as Map<String, dynamic>;
      final files = (detail['siblings'] as List? ?? []).cast<Map<String, dynamic>>()
          .where((item) => (item['rfilename'] as String).endsWith('.gguf')).toList();
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(id),
          content: SizedBox(width: 560, child: files.isEmpty
            ? const Text('Este repositorio no contiene archivos GGUF individuales. Este piloto descarga archivos GGUF públicos.')
            : ListView(shrinkWrap: true, children: [
                const Text('Los GGUF de texto de un solo archivo se cargan desde Ejecutar en este dispositivo.'),
                for (final file in files)
                  ListTile(
                    title: Text(file['rfilename'] as String),
                    subtitle: Text(file['size'] is num
                      ? '${((file['size'] as num) / 1000000000).toStringAsFixed(2)} GB'
                      : 'Tamaño no informado'),
                    onTap: () => Navigator.pop(context, file),
                  ),
              ])),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
        ),
      );
      if (selected != null) {
        await _saveFile(id, detail['sha'] as String, selected);
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'No se pudo descargar. Comprueba el espacio libre y el acceso público al archivo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveFile(String id, String revision, Map<String, dynamic> metadata) async {
    final name = metadata['rfilename'] as String;
    final support = await getApplicationSupportDirectory();
    final folder = await Directory('${support.path}/huggingface').create(recursive: true);
    final modelFolder = await Directory('${folder.path}/${id.replaceAll('/', '--')}/$revision').create(recursive: true);
    final filename = name.split('/').last;
    final destination = File('${modelFolder.path}/$filename');
    final partial = File('${destination.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    _download = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.https('huggingface.co', '/$id/resolve/$revision/$name'));
      final response = await request.close().timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) throw HttpException('Respuesta ${response.statusCode}');
      sink = partial.openWrite();
      var received = 0;
      var last = DateTime.now();
      await for (final chunk in response.timeout(const Duration(minutes: 2))) {
        sink.add(chunk);
        received += chunk.length;
        if (DateTime.now().difference(last).inMilliseconds > 300) {
          await sink.flush();
          last = DateTime.now();
          if (mounted) setState(() => _status = response.contentLength > 0
            ? 'Descargando ${(received / response.contentLength * 100).toStringAsFixed(0)} %'
            : 'Descargados ${(received / 1000000).toStringAsFixed(1)} MB');
        }
      }
      await sink.close();
      sink = null;
      if (response.contentLength >= 0 && received != response.contentLength) {
        throw const FormatException('Descarga incompleta');
      }
      final file = await partial.open();
      try {
        if (String.fromCharCodes(await file.read(4)) != 'GGUF') {
          throw const FormatException('GGUF inválido');
        }
      } finally {
        await file.close();
      }
      await partial.rename(destination.path);
      if (mounted) setState(() => _status = 'Guardado en ZASKIA: $name');
    } finally {
      await sink?.close();
      client.close(force: true);
      _download = null;
      if (await partial.exists()) await partial.delete();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hugging Face')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(controller: _search, enabled: !_busy,
          onSubmitted: (_) => _find(),
          decoration: const InputDecoration(labelText: 'Buscar modelos',
            hintText: 'Qwen, Gemma, GGUF…', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _find, child: const Text('Buscar')),
        const SizedBox(height: 12),
        Text(_status),
        if (_busy) ...[
          const LinearProgressIndicator(),
          TextButton(onPressed: () => _download?.close(force: true),
            child: const Text('Cancelar descarga')),
        ],
        for (final model in _results)
          ListTile(
            title: Text(model['id'] as String),
            subtitle: Text('${model['pipeline_tag'] ?? 'Modelo'} · ${model['downloads'] ?? 0} descargas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _files(model['id'] as String),
          ),
      ]),
    )),
  );
}
