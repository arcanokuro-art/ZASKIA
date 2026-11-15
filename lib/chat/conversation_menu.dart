import 'package:flutter/material.dart';

import '../workspace/project_store.dart';

enum ConversationAction {
  rename, pin, lock, archive, remove, move, ungroup,
}

class ConversationMenu extends StatelessWidget {
  const ConversationMenu({super.key, required this.project, required this.onAction});
  final Project project;
  final ValueChanged<ConversationAction> onAction;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ConversationAction>(
    tooltip: 'Acciones del chat',
    onSelected: onAction,
    itemBuilder: (context) {
      final danger = Theme.of(context).brightness == Brightness.dark
        ? Colors.red.shade200 : Colors.red.shade800;
      return [
        _item(ConversationAction.rename, Icons.edit_outlined, 'Renombrar'),
        _item(ConversationAction.pin, Icons.push_pin_outlined, project.pinned ? 'Desfijar' : 'Fijar'),
        _item(ConversationAction.lock, Icons.lock_outline, project.locked ? 'Quitar bloqueo' : 'Bloquear chat'),
        const PopupMenuDivider(),
        _item(ConversationAction.archive, Icons.archive_outlined, project.archived ? 'Desarchivar' : 'Archivar'),
        _item(ConversationAction.remove, Icons.delete_outline, 'Eliminar', color: danger),
        const PopupMenuDivider(),
        _item(ConversationAction.move, Icons.drive_file_move_outline, 'Mover a un proyecto'),
        if (project.folder != null)
          _item(ConversationAction.ungroup, Icons.folder_off_outlined, 'Quitar del proyecto'),
      ];
    },
  );

  PopupMenuItem<ConversationAction> _item(
    ConversationAction action, IconData icon, String title, {Color? color}
  ) => PopupMenuItem(
    value: action,
    child: Row(children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Text(title, style: TextStyle(color: color)),
    ]),
  );
}
