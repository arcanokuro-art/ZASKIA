import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'flux_engine.dart';

class FluxModelsScreen extends StatefulWidget {
  const FluxModelsScreen({super.key, required this.engine});

  final FluxEngine engine;

  @override
  State<FluxModelsScreen> createState() => _FluxModelsScreenState();
}

class _FluxModelsScreenState extends State<FluxModelsScreen> {
  Set<FluxWeight> _installed = {};
  FluxWeight? _busy;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final installed = await widget.engine.installed();
      if (mounted) setState(() => _installed = installed);
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudieron leer los modelos de imagen.');
    }
  }

  Future<void> _import(FluxWeight weight) async {
    if (_busy != null) return;
    setState(() {
      _busy = weight;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path != null) {
        await widget.engine.install(weight, path);
        await _refresh();
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo importar. Revisa el espacio libre.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Modelos de imagen')),
    body: ListView(children: [
      const ListTile(
        title: Text('FLUX.2 klein 4B'),
        subtitle: Text('Motor local experimental. Importa los tres archivos para crear o editar imágenes.'),
      ),
      for (final weight in FluxWeight.values)
        ListTile(
          leading: Icon(_installed.contains(weight) ? Icons.check : Icons.file_open_outlined),
          title: Text(weight.label),
          subtitle: Text(_busy == weight ? 'Importando…'
            : _installed.contains(weight) ? 'Importado · toca para reemplazar' : 'Toca para importar'),
          onTap: _busy == null ? () => _import(weight) : null,
        ),
      if (_error != null) ListTile(title: Text(_error!)),
    ]),
  );
}
