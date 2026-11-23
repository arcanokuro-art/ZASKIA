import 'package:flutter/material.dart';

import 'model_runtime.dart';
import 'hugging_face_screen.dart';
import 'local_models_screen.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key, required this.runtime});
  final ModelRuntime runtime;
  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  late final _address = TextEditingController(text: widget.runtime.address);
  final _download = TextEditingController();
  List<Map<String, dynamic>> _models = [];
  bool _busy = false;
  String _status = 'Conecta Ollama en este equipo o en tu red local.';

  @override
  void dispose() {
    _address.dispose();
    _download.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _status = 'No se completó la operación. Revisa la dirección y el motor.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    widget.runtime.configure(_address.text);
    final models = await widget.runtime.models();
    await widget.runtime.save();
    if (mounted) setState(() {
      _models = models;
      _status = 'Conectado · ${models.length} modelos instalados';
    });
  }

  Future<void> _details(String name) async {
    final data = await widget.runtime.request('/api/show', method: 'POST', body: {'model': name});
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(name),
      content: SingleChildScrollView(child: SelectableText(
        'Capacidades: ${(data['capabilities'] as List? ?? []).join(', ')}\n\n'
        'Familia: ${data['details']?['family'] ?? 'Sin especificar'}\n'
        'Parámetros: ${data['details']?['parameter_size'] ?? 'Sin especificar'}\n'
        'Cuantización: ${data['details']?['quantization_level'] ?? 'Sin especificar'}',
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Modelos y conexión')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: const Text('Ejecutar en esta tablet'),
          subtitle: const Text('Cargar los GGUF descargados o importar un modelo'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => Navigator.push<void>(context, MaterialPageRoute(
            builder: (context) => LocalModelsScreen(runtime: widget.runtime),
          )).then((_) { if (mounted) setState(() {}); }),
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Hugging Face'),
          subtitle: const Text('Buscar modelos y descargar archivos GGUF'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push<void>(context, MaterialPageRoute(
            builder: (context) => const HuggingFaceScreen(),
          )),
        ),
        const SizedBox(height: 20),
        TextField(controller: _address, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Dirección de Ollama',
            hintText: 'http://192.168.1.20:11434', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : () => _run(_refresh),
          child: const Text('Conectar y actualizar')),
        const SizedBox(height: 12),
        Text(_status),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 24),
        TextField(controller: _download, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Modelo para descargar',
            hintText: 'Nombre y etiqueta del catálogo de Ollama')),
        TextButton.icon(
          onPressed: _busy ? null : () => _run(() async {
            final name = _download.text.trim();
            if (name.isEmpty) return;
            widget.runtime.configure(_address.text);
            await for (final progress in widget.runtime.stream('/api/pull', {'model': name})) {
              if (mounted) setState(() => _status = progress['total'] is num && progress['completed'] is num
                ? '${progress['status']} · ${((progress['completed'] as num) / (progress['total'] as num) * 100).toStringAsFixed(0)} %'
                : progress['status']?.toString() ?? 'Descargando…');
            }
            await _refresh();
          }),
          icon: const Icon(Icons.download_outlined), label: const Text('Descargar en el motor')),
        for (final model in _models)
          ListTile(
            title: Text(model['name'] as String),
            subtitle: Text('${((model['size'] as num? ?? 0) / 1000000000).toStringAsFixed(2)} GB'),
            leading: Radio<String>(
              value: model['name'] as String, groupValue: widget.runtime.model,
              onChanged: _busy ? null : (name) => _run(() async {
                await widget.runtime.unloadLocal();
                widget.runtime.model = name!;
                await widget.runtime.save();
                if (mounted) setState(() => _status = 'Modelo seleccionado: $name');
              })),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (action) => _run(() async {
                final name = model['name'] as String;
                if (action == 'details') {
                  await _details(name);
                  return;
                }
                final confirm = await showDialog<bool>(context: context,
                  builder: (context) => AlertDialog(
                    title: Text('¿Eliminar $name del motor?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
                    ]));
                if (confirm != true) return;
                await widget.runtime.request('/api/delete', method: 'DELETE', body: {'model': name});
                if (widget.runtime.model == name) widget.runtime.model = '';
                await _refresh();
              }),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'details', child: Text('Detalles y capacidades')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar del motor')),
              ]),
          ),
        const SizedBox(height: 24),
        const Text('Piloto de texto. Música, voz, imagen y video requieren motores adicionales.'),
      ]))),
  );
}
