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
  List<Project>? _projects;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await _store.list();
      if (mounted) setState(() {
        _projects = items;
        _error = null;
      });
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudieron abrir los proyectos.');
    }
  }

  Future<void> _name([Project? project]) async {
    if (_busy) return;
    var name = project?.name ?? '';
    final accepted = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(project == null ? 'Nuevo proyecto' : 'Renombrar proyecto'),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: Text(project == null ? 'Crear' : 'Guardar'),
          ),
        ],
      ),
    );
    if (!mounted || accepted == null) return;
    setState(() => _busy = true);
    try {
      if (project == null) {
        final created = await _store.create(accepted);
        await _open(created);
      } else {
        await _store.save(Project(project.id, accepted, project.updated, project.data));
        await _reload();
      }
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo guardar el proyecto.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Project project) async {
    if (!mounted) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (context) => ChatScreen(project: project, store: _store),
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Scaffold(
      appBar: AppBar(title: const Text('ZASKIA')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              children: [
                Text('Mesa de trabajo', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _name(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo proyecto'),
                  ),
                ),
                if (_error != null)
                  ListTile(title: Text(_error!), trailing: TextButton(
                    onPressed: _reload, child: const Text('Reintentar'),
                  ))
                else if (projects == null)
                  const LinearProgressIndicator()
                else if (projects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text('Crea un proyecto para reunir tu conversación y sus referencias.'),
                  )
                else ...[
                  const SizedBox(height: 24),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text('Continuar ${projects.first.name}'),
                    onTap: _busy ? null : () => _open(projects.first),
                  ),
                  const Divider(),
                  for (final project in projects)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(project.name),
                      onTap: _busy ? null : () => _open(project),
                      trailing: IconButton(
                        tooltip: 'Renombrar proyecto',
                        onPressed: _busy ? null : () => _name(project),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
