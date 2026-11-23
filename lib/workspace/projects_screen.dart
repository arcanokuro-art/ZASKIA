import '../localization/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../chat/conversation_menu.dart';

import '../chat/chat_screen.dart';
import 'project_store.dart';
import '../settings/app_settings.dart';

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
    final s = AppSettings.instance;
    _load(select:s.get<String>('lastProject'),create:s.get<String>('startup')=='new');
  }

  Future<void> _load({String? select, bool create = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var items = await _store.list();
      final selected = items.where((item) => item.id == select).firstOrNull;
      if (selected?.locked == true && _active?.id != selected?.id && !await _authenticate()) return;
      if (create || (selected == null && !items.any((item) => !item.archived && !item.locked))) {
        final project = await _store.create(S.t('Nuevo chat'));
        select = project.id;
        items = [project, ...items];
      }
      final active = items.firstWhere((item) => item.id == select, orElse: () => items.firstWhere((item) => !item.archived && !item.locked));
      await AppSettings.instance.set('lastProject',active.id);
      if (mounted) setState(() {
        _projects = [...items.where((item) => item.pinned), ...items.where((item) => !item.pinned)];
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
        title: Text(S.t('Renombrar conversación')),
        content: TextFormField(
          initialValue: name,
          maxLength: 80,
          autofocus: true,
          decoration: InputDecoration(labelText: S.t('Nombre')),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(S.t('Cancelar'))),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: Text(S.t('Guardar')),
          ),
        ],
      ),
    );
    if (next == null || !mounted || _busy) return;
    try {
      await _store.configure(project.id, name: next);
      await _load(select: _active?.id);
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo guardar el nombre.');
    }
  }

  Future<bool> _authenticate() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.t('El bloqueo de chats requiere autenticación de Android. No está disponible en Linux.')),
      ));
      return false;
    }
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: 'Confirma tu identidad para acceder a este chat.',
      );
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.t('Configura el bloqueo de pantalla de Android para usar esta opción.')),
        ));
      }
      return false;
    }
  }

  Future<String?> _chooseFolder() async {
    final folders = _projects.map((item) => item.folder).nonNulls.toSet();
    var name = '';
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(S.t('Mover a un proyecto')),
        children: [
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder),
              child: Text(folder),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              maxLength: 80,
              decoration: InputDecoration(labelText: S.t('Nombre del nuevo proyecto')),
              onChanged: (value) => name = value.trim(),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: Text(S.t('Crear y mover')),
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(Project project, ConversationAction action) async {
    if (_busy) return;
    if (project.locked && _active?.id != project.id && !await _authenticate()) return;
    if (!mounted) return;
    var destination = _active?.id;
    try {
      switch (action) {
        case ConversationAction.rename:
          await _rename(project);
          return;
        case ConversationAction.pin:
          await _store.configure(project.id, options: {'pinned': !project.pinned});
        case ConversationAction.lock:
          if (!project.locked && !await _authenticate()) return;
          await _store.configure(project.id, options: {'locked': !project.locked});
          if (!project.locked && destination == project.id) destination = null;
        case ConversationAction.archive:
          await _store.configure(project.id, options: {'archived': !project.archived});
          if (!project.archived && destination == project.id) destination = null;
        case ConversationAction.remove:
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(S.t('¿Eliminar conversación?')),
              content: Text(S.f('Se borrarán «{name}» y sus archivos locales.',{'name':project.name})),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(S.t('Cancelar'))),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(S.t('Eliminar'))),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          await _store.remove(project.id);
          if (destination == project.id) destination = null;
        case ConversationAction.move:
          final folder = await _chooseFolder();
          if (folder == null) return;
          await _store.configure(project.id, options: {'folder': folder});
        case ConversationAction.ungroup:
          await _store.configure(project.id, options: {'folder': null});
      }
      if (mounted) await _load(select: destination);
    } on Exception {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('No se pudo completar la acción.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (_error != null || active == null) {
      return Scaffold(body: Center(
        child: _error == null
          ? CircularProgressIndicator()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(S.t(_error!)),
              TextButton(onPressed: _load, child: Text(S.t('Reintentar'))),
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
      onConversationAction: _busy ? null : _onAction,
    );
  }
}
