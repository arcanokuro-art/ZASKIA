import '../localization/strings.dart';
import 'dart:io';

import 'package:flutter/material.dart';

class ProjectReference {
  ProjectReference(this.name, this.path, this.image, {this.selected = true});

  factory ProjectReference.fromJson(Map<String, dynamic> json) => ProjectReference(
    json['name'] as String,
    json['path'] as String,
    json['image'] as bool,
    selected: json['selected'] as bool? ?? true,
  );

  final String name;
  final String path;
  final bool image;
  final bool selected;

  Map<String, Object> toJson() => {
    'name': name, 'path': path, 'image': image, 'selected': selected,
  };
}

class ReferencesPanel extends StatelessWidget {
  const ReferencesPanel({
    super.key,
    required this.references,
    required this.note,
    required this.onNoteChanged,
    required this.onAdd,
    required this.onToggle,
    required this.onRemove,
  });

  final List<ProjectReference> references;
  final TextEditingController note;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback? onAdd;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(S.t('Referencias'), style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: Icon(Icons.attach_file),
            label: Text(S.t('Agregar archivos')),
          ),
          SizedBox(height: 12),
          for (final (index, reference) in references.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: reference.selected,
                onChanged: (_) => onToggle(index),
              ),
              title: Text(reference.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: reference.image
                ? Image.file(File(reference.path), fit: BoxFit.cover,
                    height: 64, cacheWidth: 256,
                    errorBuilder: (_, __, ___) => Text(S.t('Vista previa no disponible')))
                : null,
              trailing: IconButton(
                tooltip: S.t('Quitar referencia'),
                onPressed: () => onRemove(index),
                icon: Icon(Icons.close, size: 18),
              ),
              onTap: reference.image ? () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(reference.name),
                  content: InteractiveViewer(
                    child: Image.file(File(reference.path), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Text(S.t('Vista previa no disponible'))),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context),
                    child: Text(S.t('Cerrar')))],
                ),
              ) : null,
            ),
          SizedBox(height: 16),
          TextField(
            controller: note,
            onChanged: onNoteChanged,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: S.t('Nota del proyecto'),
              hintText: S.t('Conservar expresión, ropa y fondo'),
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 8),
          Text(S.t('La nota y los archivos marcados se incluyen al enviar.')),
        ],
      ),
    ),
  );
}
