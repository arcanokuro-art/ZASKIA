import 'package:flutter/material.dart';

class ChatNavigation extends StatelessWidget {
  const ChatNavigation({
    super.key,
    required this.onNewChat,
    required this.onOpenPage,
  });

  final VoidCallback onNewChat;
  final ValueChanged<String> onOpenPage;

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
