import '../localization/strings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../storage/download_manager.dart';
import '../settings/app_settings.dart';

class HuggingFaceScreen extends StatefulWidget {
  const HuggingFaceScreen({super.key});
  @override
  State<HuggingFaceScreen> createState() => _HuggingFaceScreenState();
}

class _HuggingFaceScreenState extends State<HuggingFaceScreen> {
  final _search = TextEditingController();
  final _client = HttpClient()..connectionTimeout = Duration(seconds: 15);
  List<Map<String, dynamic>> _results = [];
  bool _busy = false;
  String _status = 'Busca repositorios públicos por nombre.';
  final _downloads = DownloadManager.instance;

  @override
  void dispose() {
    _client.close(force: true);

    _search.dispose();
    super.dispose();
  }

  Future<dynamic> _json(Uri uri) async {
    if (!AppSettings.instance.get<bool>('allowNetwork')) throw StateError('Acceso a red desactivado.');
    final request = await _client.getUrl(uri);
    final response = await request.close().timeout(Duration(seconds: 30));
    if (response.statusCode != 200) throw HttpException('Respuesta ${response.statusCode}');
    return jsonDecode(await response.transform(utf8.decoder).join()
      .timeout(Duration(seconds: 30)));
  }

  Future<void> _find() async {
    if (_busy || _search.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = await _json(Uri.https('huggingface.co', '/api/models', {
        'search': _search.text.trim(), 'limit': '25', 'sort': 'downloads', 'direction': '-1',
      })) as List;
      if (mounted) setState(() {
        _results = data.cast<Map<String, dynamic>>();
        _status = S.f('{count} resultados · catálogo de Hugging Face',{'count':data.length});
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'No se pudo consultar Hugging Face. Reintenta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _files(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final detail = await _json(Uri.https('huggingface.co', '/api/models/$id', {'blobs': 'true'}))
          as Map<String, dynamic>;
      final files = (detail['siblings'] as List? ?? []).cast<Map<String, dynamic>>()
          .where((item) => RegExp(r'\.(gguf|safetensors|bin|onnx|pt|pth|json|model|txt|yaml|yml)$',caseSensitive:false).hasMatch(item['rfilename'] as String)).toList();
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(id),
          content: SizedBox(width: 560, child: files.isEmpty
            ? Text(S.t('Este repositorio no contiene archivos compatibles para descargar.'))
            : ListView(shrinkWrap: true, children: [
                Text(S.t('Los GGUF de texto se cargan en el motor integrado. Otros formatos necesitan un motor compatible y pueden requerir varios archivos.')),
                for (final file in files)
                  ListTile(
                    title: Text(file['rfilename'] as String),
                    subtitle: Text(file['size'] is num
                      ? '${((file['size'] as num) / 1000000000).toStringAsFixed(2)} GB'
                      : 'Tamaño no informado'),
                    onTap: () => Navigator.pop(context, file),
                  ),
              ])),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(S.t('Cerrar')))],
        ),
      );
      if (selected != null) {
        await _saveFile(id, detail['sha'] as String, selected);
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'No se pudo descargar. Comprueba el espacio libre y el acceso público al archivo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveFile(String id, String revision, Map<String, dynamic> metadata) async {
    if (!AppSettings.instance.get<bool>('allowNetwork')) throw StateError('Acceso a red desactivado.');
    final size = metadata['size'] as num?;
    if (size == null || size > AppSettings.instance.get<int>('largeDownloadMB') * 1000000) {
      final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(S.t('Confirmar descarga')),
        content: Text(size == null ? 'Tamaño no informado' : '${(size / 1000000000).toStringAsFixed(2)} GB'),
        actions: [TextButton(onPressed:()=>Navigator.pop(context,false), child:Text(S.t('Cancelar'))),
          FilledButton(onPressed:()=>Navigator.pop(context,true), child:Text(S.t('Descargar')))],
      ));
      if (approved != true) return;
    }
    await _downloads.enqueue(id,revision,metadata);
    if(mounted)setState(()=>_status='Descarga añadida a la cola');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation:_downloads,builder:(context,_)=>Scaffold(
    appBar: AppBar(title: Text(S.t('Hugging Face'))),
    body: Center(child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 820),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(controller: _search, enabled: !_busy,
          onSubmitted: (_) => _find(),
          decoration: InputDecoration(labelText: S.t('Buscar modelos'),
            hintText: S.t('Qwen, Gemma, GGUF…'), border: OutlineInputBorder())),
        SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _find, child: Text(S.t('Buscar'))),
        SizedBox(height: 12),
        Text(S.t(_status)),
        if (_busy) ...[
          LinearProgressIndicator(),

        ],
        for (final task in _downloads.tasks.reversed)
          ListTile(title:Text(task.name),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(S.t(task.status)),if(!task.finished)LinearProgressIndicator(value:task.progress)]),
            trailing:task.finished?null:IconButton(tooltip:S.t('Cancelar descarga'),icon:const Icon(Icons.close),onPressed:()=>_downloads.cancel(task))),
        for (final model in _results)
          ListTile(
            title: Text(model['id'] as String),
            subtitle: Text('${model['pipeline_tag'] ?? 'Modelo'} · ${S.f('{count} descargas',{'count':model['downloads'] ?? 0})}'),
            trailing: Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _files(model['id'] as String),
          ),
      ]),
    )),
  ));
}
