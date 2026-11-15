import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaskia/workspace/project_store.dart';

void main() {
  test('reopens a project with its latest draft and a copied reference', () async {
    final directory = await Directory.systemTemp.createTemp('zaskia-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ProjectStore(directory: directory);
    final project = await store.create('Personajes');
    final original = await File('${directory.path}/original.txt').writeAsString('Ficha');
    final copied = await store.copyAttachment(project.id, original.path);
    await original.delete();
    await Future.wait([
      store.save(Project(project.id, project.name, 1, {'draft': 'Primero'})),
      store.save(Project(project.id, 'Capítulo 3', 2, {
        'draft': 'Último borrador',
        'note': 'Conservar expresión',
        'references': [copied],
        'messages': ['Hola'],
      })),
    ]);
    final reopened = (await ProjectStore(directory: directory).list()).single;
    expect(reopened.name, 'Capítulo 3');
    expect(reopened.data['draft'], 'Último borrador');
    expect(reopened.data['note'], 'Conservar expresión');
    expect(reopened.data['messages'], ['Hola']);
    expect(await File((reopened.data['references'] as List).single as String)
        .readAsString(), 'Ficha');
  });
}
