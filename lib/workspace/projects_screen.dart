import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import 'project_store.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _store = ProjectStore();
  List<Project> _projects = [];
  Project? _active;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? select, bool create = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var items = await _store.list();
      if (create || items.isEmpty) {
        final project = await _store.create('Nuevo chat');
        select = project.id;
        items = [project, ...items];
      }
      final active = items.firstWhere((item) => item.id == select, orElse: () => items.first);
      if (mounted) setState(() {
        _projects = items;
        _active = active;
      });
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo abrir el historial local.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Project project) async {
    if (_busy) return;
    var name = project.name;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar conversación'),
        content: TextFormField(
          initialValue: name,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (next == null || !mounted || _busy) return;
    try {
      final latest = (await _store.list()).firstWhere((item) => item.id == project.id);
      await _store.save(Project(latest.id, next, latest.updated, latest.data));
      await _load(select: _active?.id);
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo guardar el nombre.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (_error != null || active == null) {
      return Scaffold(body: Center(
        child: _error == null
          ? const CircularProgressIndicator()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ]),
      ));
    }
    return ChatScreen(
      key: ValueKey(active.id),
      project: active,
      store: _store,
      projects: _projects,
      onNewConversation: _busy ? null : () => _load(create: true),
      onSelectConversation: _busy ? null : (id) => _load(select: id),
      onRenameConversation: _busy ? null : _rename,
    );
  }
}
