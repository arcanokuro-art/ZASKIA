import 'package:flutter/material.dart';

import '../workspace/project_store.dart';

class ChatNavigation extends StatelessWidget {
  const ChatNavigation({
    super.key,
    required this.onNewChat,
    required this.onOpenPage,
    required this.projects,
    required this.activeId,
    required this.onSelect,
    required this.onRename,
  });

  final VoidCallback onNewChat;
  final ValueChanged<String> onOpenPage;
  final List<Project> projects;
  final String? activeId;
  final ValueChanged<Project> onSelect;
  final ValueChanged<Project> onRename;

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
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Nuevo chat'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 48),
              ),
            ),
            if (projects.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 18, 12, 6),
                child: Text('Conversaciones'),
              ),
              for (final project in projects)
                ListTile(
                  dense: true,
                  selected: project.id == activeId,
                  selectedTileColor: colors.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => onSelect(project),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Opciones de conversación',
                    onSelected: (_) => onRename(project),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                    ],
                  ),
                ),
              const Divider(height: 28),
            ] else
              const SizedBox(height: 16),
            for (final entry in const {
              'Modelos locales': Icons.memory_outlined,
              'Ajustes': Icons.settings_outlined,
            }.entries)
              ListTile(
                leading: Icon(entry.value),
                title: Text(entry.key),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => onOpenPage(entry.key),
              ),
          ],
        ),
      ),
    );
  }
}
