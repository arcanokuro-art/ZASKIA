part of 'chat_screen.dart';

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, this.onRemove});

  final _Attachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 112,
      height: 68,
      padding: const EdgeInsets.all(8),
      color: colors.surface,
      child: Row(children: [
        const Icon(Icons.insert_drive_file_outlined, size: 18),
        const SizedBox(width: 5),
        Expanded(child: Text(attachment.name, maxLines: 2,
          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
      ]),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        if (attachment.image)
          Image.file(File(attachment.path),
            semanticLabel: attachment.name,
            width: 112, height: 68, cacheWidth: 336, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback)
        else
          fallback,
        if (onRemove != null)
          Positioned(top: 0, right: 0, child: IconButton(
            tooltip: 'Quitar adjunto',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black87, foregroundColor: Colors.white,
            ),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
          )),
      ]),
    );
  }
}
