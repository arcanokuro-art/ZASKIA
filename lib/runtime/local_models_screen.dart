import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'downloaded_models.dart';
import 'model_runtime.dart';
import 'model_info.dart';

class LocalModelsScreen extends StatefulWidget {
  const LocalModelsScreen({super.key, required this.runtime});
  final ModelRuntime runtime;
  @override
  State<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends State<LocalModelsScreen> {
  final _library = DownloadedModels();
  List<File> _files = [];
  bool _busy = false;
  Map<String, ModelInfo> _details = {};
  List<Map<String, dynamic>> _remote = [];
  String? _remoteStatus;
  String _status = 'Selecciona un GGUF de texto para ejecutarlo en esta tablet.';

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  Future<void> _refresh() async {
    final files = await _library.list();
    final details = <String, ModelInfo>{};
    for (final file in files) {
      try {
        details[file.path] = await ModelInfo.inspect(file);
      } on Exception {
        // A download or import may have changed since the scan.
      }
    }
    var remote = <Map<String, dynamic>>[];
    String? remoteStatus;
    if (widget.runtime.address.isNotEmpty) {
      try {
        remote = await widget.runtime.models();
      } on Exception {
        remoteStatus = 'No se pudo consultar el motor conectado.';
      }
    }
    if (mounted) setState(() {
      _files = files;
      _details = details;
      _remote = remote;
      _remoteStatus = remoteStatus;
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _status = 'No se pudo cargar o importar. Revisa el formato, la compatibilidad del modelo y la memoria disponible.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDetails(File file) async {
    final info = _details[file.path];
    if (info == null) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(_library.name(file)),
      content: SizedBox(width: 560, child: SingleChildScrollView(
        child: SelectableText([
          'Ubicación\n${info.path}',
          'Tamaño\n${info.size} · ${info.bytes} bytes',
          'Formato\n${info.format}',
          'Capacidades\n${info.capabilities}',
          'Motor\n${info.engine}',
          for (final entry in info.metadata.entries) '${entry.key}\n${entry.value}',
        ].join('\n\n')),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    ));
  }

  Future<void> _showRemote(Map<String, dynamic> model) async {
    final name = model['name'] as String;
    final info = await widget.runtime.request('/api/show', method: 'POST', body: {'model': name});
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(name),
      content: SingleChildScrollView(child: SelectableText([
        'Ubicación\nMotor Ollama: ${widget.runtime.address}\nLa API no informa la ruta física.',
        'Tamaño\n${((model['size'] as num? ?? 0) / 1000000000).toStringAsFixed(2)} GB',
        'Formato\n${info['details']?['format'] ?? 'No informado'}',
        'Arquitectura\n${info['details']?['family'] ?? 'No informada'}',
        'Cuantización\n${info['details']?['quantization_level'] ?? 'No informada'}',
        'Capacidades\n${(info['capabilities'] as List? ?? []).join(', ')}',
        'Motor\nOllama conectado',
      ].join('\n\n'))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Biblioteca de modelos')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Text(_status),
      const SizedBox(height: 12),
      const Text('Modelos de texto GGUF de un solo archivo. CPU · contexto de 2048 tokens.'),
      if (_busy) const LinearProgressIndicator(),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(() async {
            final selected = await FilePicker.platform.pickFiles();
            final path = selected?.files.single.path;
            if (path == null) return;
            await _library.import(path);
            await _refresh();
            if (mounted) setState(() => _status = 'Modelo importado. Selecciona Cargar para usarlo.');
          }),
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Importar GGUF'),
        ),
        TextButton(onPressed: _busy ? null : () => _run(_refresh), child: const Text('Actualizar')),
        TextButton(
          onPressed: _busy ? null : () => _run(() async {
            await widget.runtime.unloadLocal();
            if (mounted) setState(() => _status = 'Modelo liberado de la memoria.');
          }),
          child: const Text('Liberar memoria'),
        ),
      ]),
      if (_files.isEmpty && !_busy)
        const ListTile(title: Text('Descarga un GGUF desde Hugging Face o importa uno.')),
      if (_files.isNotEmpty) const ListTile(title: Text('En este dispositivo')),
      for (final file in _files)
        ListTile(
          onTap: () => _showDetails(file),
          title: Text(_library.name(file)),
          subtitle: Text('${_details[file.path]?.size ?? 'Tamaño pendiente'} · ${_details[file.path]?.format ?? 'GGUF'}\\n'.replaceAll(r'\n', '\n') + (!_library.singleFile(file) ? 'Modelo dividido: requiere todos sus componentes'
            : widget.runtime.localPath == file.path && widget.runtime.useLocal
              ? 'Seleccionado para el chat'
              : 'Disponible en el dispositivo') + '\n${_details[file.path]?.capabilities ?? 'Capacidades por comprobar'}'),
          trailing: FilledButton(
            onPressed: _busy || !_library.singleFile(file) ? null : () => _run(() async {
              setState(() => _status = 'Cargando ${_library.name(file)}…');
              await widget.runtime.selectLocal(file.path);
              if (mounted) setState(() => _status = 'Listo. Regresa al chat para conversar sin conexión.');
            }),
            child: const Text('Cargar'),
          ),
        ),
      if (_remoteStatus != null) ListTile(title: Text(_remoteStatus!)),
      if (_remote.isNotEmpty) ...[
        const Divider(),
        ListTile(title: const Text('En el motor conectado'),
          subtitle: Text(widget.runtime.address)),
        for (final model in _remote)
          ListTile(
            leading: const Icon(Icons.computer_outlined),
            title: Text(model['name'] as String),
            subtitle: Text('${((model['size'] as num? ?? 0) / 1000000000).toStringAsFixed(2)} GB · Ollama'),
            trailing: const Icon(Icons.info_outline),
            onTap: _busy ? null : () => _run(() => _showRemote(model)),
          ),
      ],
    ]),
  );
}
