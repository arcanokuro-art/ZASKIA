import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ModelRuntime {
  String address = '';
  String model = '';
  HttpClient? _generation;

  Future<File> _settings() async => File(
    '${(await getApplicationSupportDirectory()).path}/runtime.json',
  );

  Future<void> load() async {
    final file = await _settings();
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    address = data['address'] as String? ?? '';
    model = data['model'] as String? ?? '';
  }

  void configure(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Escribe una dirección HTTP o HTTPS válida.');
    }
    address = uri.toString().replaceFirst(RegExp(r'/$'), '');
  }

  Future<void> save() async {
    final file = await _settings();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode({'address': address, 'model': model}), flush: true);
    await temporary.rename(file.path);
  }

  Future<Map<String, dynamic>> request(String endpoint, {String method = 'GET',
      Map<String, dynamic>? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, Uri.parse('$address$endpoint'));
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final text = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 45));
      if (response.statusCode >= 400) throw HttpException('El motor devolvió ${response.statusCode}.');
      return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> models() async =>
      ((await request('/api/tags'))['models'] as List? ?? []).cast<Map<String, dynamic>>();

  Stream<Map<String, dynamic>> stream(String endpoint, Map<String, dynamic> body) async* {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    _generation = client;
    try {
      final request = await client.postUrl(Uri.parse('$address$endpoint'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode >= 400) throw HttpException('El motor devolvió ${response.statusCode}.');
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())
          .timeout(const Duration(minutes: 3))) {
        if (line.trim().isEmpty) continue;
        final data = jsonDecode(line) as Map<String, dynamic>;
        if (data['error'] != null) throw StateError(data['error'].toString());
        yield data;
      }
    } finally {
      client.close(force: true);
      if (identical(_generation, client)) _generation = null;
    }
  }

  void stop() => _generation?.close(force: true);
}
