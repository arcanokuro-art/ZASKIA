import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Range downloads only append a server-confirmed byte interval. No model is
/// published until its length, optional digest and format have been checked.
class ResumableTransfer {
  ResumableTransfer({this.availableBytes = availableDiskBytes});
  final Future<int?> Function(String path) availableBytes;
  static Future<int?> availableDiskBytes(String path) async {
    if(!Platform.isLinux && !Platform.isAndroid)return null;
    try {
      final result=await Process.run('df',['-Pk',path]).timeout(const Duration(seconds:3));
      if(result.exitCode!=0)return null;
      final lines=(result.stdout as String).trim().split('\n');
      final columns=lines.last.trim().split(RegExp(r'\s+'));
      return columns.length>=4 ? int.tryParse(columns[3])==null?null:int.parse(columns[3])*1024 : null;
    }catch(_){return null;}
  }
  HttpClient? _client;
  bool stopped = false;
  void stop() { stopped = true; _client?.close(force: true); }
  Future<void> fetch(Uri url, File partial, {int? expectedSize, String? sha,
      bool gguf = false, void Function(int received, int? total)? progress}) async {
    stopped = false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _client = client;
    IOSink? sink;
    try {
      await partial.parent.create(recursive: true);
      var offset = await partial.exists() ? await partial.length() : 0;
      if (expectedSize != null && offset > expectedSize) { await partial.delete(); offset = 0; }
      if (expectedSize == null || offset != expectedSize) {
        final request = await client.getUrl(url);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (offset > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        final response = await request.close().timeout(const Duration(seconds: 45));
        if (response.statusCode == 206) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(response.headers.value('content-range') ?? '');
          if (range == null || int.parse(range[1]!) != offset ||
              (expectedSize != null && int.parse(range[3]!) != expectedSize)) {
            throw const FormatException('El servidor devolvió un rango incompatible.');
          }
          expectedSize ??= int.parse(range[3]!);
        } else if (response.statusCode == 200) {
          offset = 0; // Range ignored: restart, never append the whole response.
          if (expectedSize != null && response.contentLength >= 0 && response.contentLength != expectedSize) {
            throw const FormatException('El tamaño no coincide con el catálogo.');
          }
        } else {
          throw HttpException('HTTP ${response.statusCode}');
        }
        final total = expectedSize ?? (response.contentLength < 0 ? null : offset + response.contentLength);
        if(total!=null){final free=await availableBytes(partial.parent.path);if(free!=null&&free<total-offset+67108864)throw const FileSystemException('Espacio insuficiente para completar la descarga.');}
        sink = partial.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
        var received = offset;
        await for (final chunk in response.timeout(const Duration(minutes: 2))) {
          if (stopped) throw const HttpException('Descarga detenida.');
          sink.add(chunk); received += chunk.length;
          if (total != null && received > total) throw const FormatException('Tamaño excedido.');
          progress?.call(received, total);
        }
        await sink.close(); sink = null;
        if (total != null && received != total) throw const FormatException('Descarga incompleta.');
      }
      if (stopped) throw const HttpException('Descarga detenida.');
      if (sha != null && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString() != sha.toLowerCase()) {
          await partial.delete();
          throw const FormatException('SHA-256 incorrecto. Reintenta la descarga.');
        }
      }
      if (gguf) {
        final file = await partial.open();
        try { if (String.fromCharCodes(await file.read(4)) != 'GGUF') {
          await file.close(); await partial.delete();
          throw const FormatException('El archivo no es GGUF.');
        }} finally { try { await file.close(); } catch (_) {} }
      }
    } finally { try { await sink?.close(); } finally { client.close(force: true); _client = null; } }
  }
}
