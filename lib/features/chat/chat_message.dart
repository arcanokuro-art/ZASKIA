part of 'chat_screen.dart';

enum _Mode { chat, create, edit }
enum _Action { camera, photos, files, create, edit }

class _Attachment {
  const _Attachment(this.name, this.path, {this.image = false});

  final String name;
  final String path;
  final bool image;
}

class _Message {
  _Message(this.text, this.attachments, this.mode);

  String answer = '';
  File? generatedImage;
  String? imageError;
  bool generatingImage = false;

  final String text;
  final List<_Attachment> attachments;
  final _Mode mode;
}

