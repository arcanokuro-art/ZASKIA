import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Project {
  Project(this.id, this.name, this.updated, this.data, {this.options = const {}});

  final Map<String, dynamic> options;
  bool get pinned => options['pinned'] == true;
  bool get archived => options['archived'] == true;
  bool get locked => options['locked'] == true;
  String? get folder => options['folder'] as String?;

  final String id;
  final String name;
  final int updated;
  final Map<String, dynamic> data;
}

class ProjectStore {
  ProjectStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;
  Future<void> _writes = Future.value();

  Future<Directory> _root() async =>
      _directory ?? Directory('${(await getApplicationSupportDirectory()).path}/projects');

  Future<List<Project>> list() async {
    await _writes;
    final root = await _root();
    if (!await root.exists()) return [];
    final projects = <Project>[];
    await for (final entry in root.list()) {
      if (entry is! Directory || entry.uri.pathSegments.any((part) => part.startsWith('.deleted-'))) continue;
      final file = File('${entry.path}/project.json');
      if (!await file.exists()) continue;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      projects.add(Project(
        json['id'] as String,
        json['name'] as String,
        json['updated'] as int,
        json['data'] as Map<String, dynamic>,
        options: json['options'] as Map<String, dynamic>? ?? {},
      ));
    }
    return projects..sort((a, b) => b.updated.compareTo(a.updated));
  }

  Future<Project> create(String name) async {
    final root = await _root();
    await root.create(recursive: true);
    final directory = await root.createTemp('project-');
    final id = directory.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    final project = Project(id, name, DateTime.now().millisecondsSinceEpoch, {});
    await save(project);
    return project;
  }

  Future<void> _queue(Future<void> Function() operation) {
    final write = _writes.then((_) => operation());
    _writes = write.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return write;
  }

  Future<void> save(Project project, {bool preserveOptions = false}) => _queue(() async {
    final root = await _root();
    final target = File('${root.path}/${project.id}/project.json');
    final prior = preserveOptions
      ? jsonDecode(await target.readAsString()) as Map<String, dynamic>
      : null;
    await _write(target, {
      'id': project.id,
      'name': prior?['name'] ?? project.name,
      'updated': project.updated,
      'data': project.data,
      'options': prior?['options'] ?? project.options,
    });
  });

  Future<void> configure(String id, {String? name, Map<String, Object?> options = const {}}) =>
      _queue(() async {
        final root = await _root();
        final target = File('${root.path}/$id/project.json');
        final current = jsonDecode(await target.readAsString()) as Map<String, dynamic>;
        if (name != null) current['name'] = name;
        current['options'] = {...?current['options'] as Map<String, dynamic>?, ...options};
        await _write(target, current);
      });

  Future<void> remove(String id) => _queue(() async {
    final root = await _root();
    final directory = Directory('${root.path}/$id');
    final removed = await directory.rename('${root.path}/.deleted-$id');
    await removed.delete(recursive: true);
  });

  Future<void> _write(File target, Map<String, dynamic> data) async {
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(target.path);
  }

  Future<String> copyAttachment(String project, String original) async {
    final root = await _root();
    final directory = await Directory('${root.path}/$project').createTemp('attachment-');
    try {
      return (await File(original).copy('${directory.path}/content')).path;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }
}
