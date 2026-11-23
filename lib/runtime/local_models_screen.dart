import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'downloaded_models.dart';
import 'model_runtime.dart';

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
  String _status = 'Selecciona un GGUF de texto para ejecutarlo en esta tablet.';

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  Future<void> _refresh() async {
    final files = await _library.list();
    if (mounted) setState(() => _files = files);
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ejecutar en esta tablet')),
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
      for (final file in _files)
        ListTile(
          title: Text(_library.name(file)),
          subtitle: Text(!_library.singleFile(file) ? 'Modelo dividido: requiere todos sus componentes'
            : widget.runtime.localPath == file.path && widget.runtime.useLocal
              ? 'Seleccionado para el chat'
              : 'Disponible en el dispositivo'),
          trailing: FilledButton(
            onPressed: _busy || !_library.singleFile(file) ? null : () => _run(() async {
              setState(() => _status = 'Cargando ${_library.name(file)}…');
              await widget.runtime.selectLocal(file.path);
              if (mounted) setState(() => _status = 'Listo. Regresa al chat para conversar sin conexión.');
            }),
            child: const Text('Cargar'),
          ),
        ),
    ]),
  );
}
