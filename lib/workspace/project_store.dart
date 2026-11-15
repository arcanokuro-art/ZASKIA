import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Project {
  Project(this.id, this.name, this.updated, this.data);

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
      if (entry is! Directory) continue;
      final file = File('${entry.path}/project.json');
      if (!await file.exists()) continue;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      projects.add(Project(
        json['id'] as String,
        json['name'] as String,
        json['updated'] as int,
        json['data'] as Map<String, dynamic>,
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

  Future<void> save(Project project) {
    final payload = jsonEncode({
      'id': project.id,
      'name': project.name,
      'updated': project.updated,
      'data': project.data,
    });
    final write = _writes.then((_) async {
      final root = await _root();
      final temporary = File('${root.path}/${project.id}/project.json.tmp');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename('${root.path}/${project.id}/project.json');
    });
    _writes = write.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return write;
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
