import '../localization/strings.dart';
import 'package:flutter/material.dart';

import '../workspace/project_store.dart';
import 'conversation_menu.dart';

class ChatNavigation extends StatelessWidget {
  const ChatNavigation({
    super.key,
    required this.onNewChat,
    required this.onOpenPage,
    required this.projects,
    required this.activeId,
    required this.onSelect,
    required this.onAction,
  });

  final VoidCallback onNewChat;
  final ValueChanged<String> onOpenPage;
  final List<Project> projects;
  final String? activeId;
  final ValueChanged<Project> onSelect;
  final void Function(Project, ConversationAction) onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainer,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          children: [
            TextButton.icon(
              onPressed: onNewChat,
              icon: Icon(Icons.add_comment_outlined),
              label: Text(S.t('Nuevo chat')),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: Size(0, 48),
              ),
            ),
            if (projects.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(12, 18, 12, 6),
                child: Text(S.t('Conversaciones')),
              ),
              for (final project in projects.where((item) => !item.archived && item.folder == null))
                _conversation(context, project),
              for (final folder in projects.where((item) => !item.archived)
                  .map((item) => item.folder).nonNulls.toSet())
                ExpansionTile(
                  key: PageStorageKey(folder),
                  leading: Icon(Icons.folder_outlined),
                  title: Text(folder),
                  initiallyExpanded: projects.any((item) => item.id == activeId && item.folder == folder),
                  children: [
                    for (final project in projects.where((item) => !item.archived && item.folder == folder))
                      _conversation(context, project),
                  ],
                ),
              if (projects.any((item) => item.archived))
                ExpansionTile(
                  leading: Icon(Icons.archive_outlined),
                  title: Text(S.t('Archivados')),
                  children: [
                    for (final project in projects.where((item) => item.archived))
                      _conversation(context, project),
                  ],
                ),
              Divider(height: 28),
            ] else
              SizedBox(height: 16),
            for (final entry in {
              'Modelos locales': Icons.memory_outlined,
              'Guía de inicio': Icons.explore_outlined,
              'Gestor de motores': Icons.hub_outlined,
              'Descargas': Icons.download_outlined,
              'Configuración de ejecución': Icons.tune,
              'Estudio multimedia': Icons.auto_awesome_outlined,
              'Importar conversación': Icons.file_upload_outlined,
              'Ajustes': Icons.settings_outlined,
            }.entries)
              ListTile(
                leading: Icon(entry.value),
                title: Text(S.t(entry.key)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => onOpenPage(entry.key),
              ),
          ],
        ),
      ),
    );
  }
  Widget _conversation(BuildContext context, Project project) => ListTile(
    dense: true,
    selected: project.id == activeId,
    selectedTileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    leading: project.locked ? Icon(Icons.lock_outline, size: 16)
      : project.pinned ? Icon(Icons.push_pin_outlined, size: 16) : null,
    title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () => onSelect(project),
    trailing: ConversationMenu(
      project: project,
      onAction: (action) => onAction(project, action),
    ),
  );
}
