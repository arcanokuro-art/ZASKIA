import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum _Mode { chat, create, edit }
enum _Action { camera, photos, files, create, edit }

class _Attachment {
  const _Attachment(this.name, this.path, {this.image = false});

  final String name;
  final String path;
  final bool image;
}

class _Message {
  const _Message(this.text, this.attachments, this.mode);

  final String text;
  final List<_Attachment> attachments;
  final _Mode mode;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final _messages = <_Message>[];
  final _attachments = <_Attachment>[];
  _Mode _mode = _Mode.chat;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _recoverImages();
  }

  @override
  void dispose() {
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _recoverImages() async {
    try {
      final result = await _picker.retrieveLostData();
      if (!mounted || result.isEmpty) return;
      if (result.exception != null) throw result.exception!;
      final files = result.files ?? [];
      setState(() => _attachments.addAll(files.map(_photo)));
    } on Exception {
      if (mounted) _notice('No se pudo recuperar la foto.');
    }
  }

  _Attachment _photo(XFile file) =>
      _Attachment(file.name, file.path, image: true);

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick(_Action action) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final List<_Attachment> selected;
      switch (action) {
        case _Action.camera:
          final file = await _picker.pickImage(source: ImageSource.camera);
          selected = [if (file != null) _photo(file)];
        case _Action.photos:
          selected = (await _picker.pickMultiImage()).map(_photo).toList();
        case _Action.files:
          final result = await FilePicker.platform.pickFiles(allowMultiple: true);
          selected = [
            for (final file in result?.files ?? <PlatformFile>[])
              if (file.path case final String path)
                _Attachment(file.name, path, image: _isImage(file.extension)),
          ];
        case _Action.create:
        case _Action.edit:
          return;
      }
      if (!mounted) return;
      setState(() => _attachments.addAll(selected));
    } on Exception {
      if (mounted) _notice('No se pudo abrir el selector. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _isImage(String? extension) => const {
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif',
  }.contains(extension?.toLowerCase());

  void _setMode(_Mode mode) {
    setState(() => _mode = mode);
    _focus.requestFocus();
  }

  Future<void> _handleAction(_Action action) async {
    switch (action) {
      case _Action.create:
        _setMode(_Mode.create);
      case _Action.edit:
        _setMode(_Mode.edit);
      case _Action.camera:
      case _Action.photos:
      case _Action.files:
        _focus.unfocus();
        await _pick(action);
    }
  }

  bool get _canSend => !_picking &&
      (_composer.text.trim().isNotEmpty || _attachments.isNotEmpty);

  void _send() {
    if (!_canSend) return;
    final text = _composer.text.trim();
    if (_mode != _Mode.chat && text.isEmpty) {
      _notice('Escribe lo que quieres hacer con la imagen.');
      return;
    }
    if (_mode == _Mode.edit && !_attachments.any((item) => item.image)) {
      _notice('Agrega una imagen para editar.');
      return;
    }
    setState(() {
      _messages.add(_Message(text, List.of(_attachments), _mode));
      _attachments.clear();
      _mode = _Mode.chat;
      _composer.clear();
    });
    _focus.unfocus();
  }

  Future<void> _newChat() async {
    if (_picking) return;
    if (_messages.isNotEmpty || _attachments.isNotEmpty ||
        _composer.text.trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Iniciar un chat nuevo?'),
          content: const Text('La conversación actual y el borrador se borrarán.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Nuevo chat')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      _messages.clear();
      _attachments.clear();
      _composer.clear();
      _mode = _Mode.chat;
    });
  }

  void _openInfo(String title) {
    Navigator.push<void>(context, MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(children: [
          if (title == 'Modelos locales')
            const ListTile(
              leading: Icon(Icons.memory_outlined),
              title: Text('Modelo local sin configurar'),
              subtitle: Text('La gestión de modelos se habilitará al integrar los motores de IA.'),
            )
          else
            const ListTile(
              leading: Icon(Icons.system_update_alt),
              title: Text('ZASKIA 0.2.0'),
              subtitle: Text('Actualizaciones mediante APK firmada de GitHub Releases.'),
            ),
        ]),
      ),
    ));
  }

  Widget _drawer() => Drawer(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        children: [
          const ListTile(
            leading: _Mark(size: 32),
            title: Text('ZASKIA', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: const Text('Nuevo chat'),
            onTap: () {
              Navigator.pop(context);
              _newChat();
            },
          ),
          for (final entry in {
            'Modelos locales': Icons.memory_outlined,
            'Ajustes': Icons.settings_outlined,
          }.entries)
            ListTile(
              leading: Icon(entry.value),
              title: Text(entry.key),
              onTap: () {
                Navigator.pop(context);
                _openInfo(entry.key);
              },
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: _drawer(),
    appBar: AppBar(
      title: const Text('ZASKIA', style: TextStyle(
        fontWeight: FontWeight.w800, letterSpacing: 1.2,
      )),
      actions: [
        IconButton(
          tooltip: 'Nuevo chat',
          onPressed: _picking ? null : _newChat,
          icon: Icon(Icons.add_comment_outlined,
            color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            Expanded(
              child: _messages.isEmpty
                ? const Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        _Mark(size: 52),
                        SizedBox(height: 12),
                        Text('¿En qué te ayudo?', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _message(_messages[_messages.length - 1 - index]),
                  ),
            ),
            _input(context),
          ]),
        ),
      ),
    ),
  );

  Widget _message(_Message message) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (message.mode) {
      _Mode.chat => null,
      _Mode.create => 'Crear imagen',
      _Mode.edit => 'Editar imagen',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.only(left: 36),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2A46),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (label != null)
                Text(label, style: TextStyle(color: colors.primary)),
              if (message.attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final attachment in message.attachments)
                      _AttachmentTile(attachment: attachment),
                  ]),
                ),
              if (message.text.isNotEmpty) SelectableText(message.text),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Modelo local sin configurar',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _input(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint = switch (_mode) {
      _Mode.chat => 'Escribe un mensaje',
      _Mode.create => 'Describe la imagen que quieres crear',
      _Mode.edit => 'Describe qué quieres cambiar',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_messages.isEmpty && _mode == _Mode.chat)
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Crear imagen'),
              onPressed: _picking ? null : () => _setMode(_Mode.create),
            ),
            ActionChip(
              avatar: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar imagen'),
              onPressed: _picking ? null : () => _setMode(_Mode.edit),
            ),
          ]),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_mode != _Mode.chat)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: InputChip(
                  label: Text(_mode == _Mode.create ? 'Crear imagen' : 'Editar imagen'),
                  onDeleted: () => setState(() => _mode = _Mode.chat),
                ),
              ),
            if (_attachments.isNotEmpty)
              SizedBox(
                height: 76,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => _AttachmentTile(
                    attachment: _attachments[index],
                    onRemove: () => setState(() => _attachments.removeAt(index)),
                  ),
                ),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              PopupMenuButton<_Action>(
                tooltip: 'Adjuntar o elegir herramienta',
                enabled: !_picking,
                offset: const Offset(0, -48),
                icon: const Icon(Icons.add),
                onSelected: _handleAction,
                itemBuilder: (context) => [
                  for (final option in const [
                    (_Action.camera, Icons.photo_camera_outlined, 'Cámara'),
                    (_Action.photos, Icons.photo_library_outlined, 'Fotos'),
                    (_Action.files, Icons.attach_file, 'Archivos'),
                    (_Action.create, Icons.image_outlined, 'Crear imagen'),
                    (_Action.edit, Icons.edit_outlined, 'Editar imagen'),
                  ])
                    PopupMenuItem(
                      value: option.$1,
                      child: Row(children: [
                        Icon(option.$2, size: 20),
                        const SizedBox(width: 12),
                        Text(option.$3),
                      ]),
                    ),
                ],
              ),
              Expanded(child: TextField(
                controller: _composer,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              )),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _composer,
                builder: (context, value, child) => IconButton.filled(
                  tooltip: 'Enviar',
                  onPressed: _canSend ? _send : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ]),
          ]),
        ),
        if (_messages.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: Text('Modelo local sin configurar',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
          ),
      ]),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Text('Z', style: TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    color: Theme.of(context).colorScheme.primary,
    height: 1,
  ));
}

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
            style: IconButton.styleFrom(backgroundColor: Colors.black87),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
          )),
      ]),
    );
  }
}
