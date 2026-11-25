import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_engine/app_engine.dart';
import 'package:app_engine/src/blocks.dart';

import 'example_fixture.dart';

/// A test app as written, including app-engine's blocks.
Map<String, dynamic> exampleWithIncludes() {
  final app = exampleManifest();
  (app['screens']['home']['layout'] as Map)['children'] = [
    {
      'id': 'ping',
      'visible': {'bind': 'context.capabilities.ping'},
      'include': 'app-engine/blocks/button.yaml',
      'label': 'Ping',
      'icon': 'https://example.com/icons/ping.png',
      'call': 'com.example.ping',
    },
    {
      'id': 'light',
      'visible': {'bind': 'context.capabilities.light'},
      'include': 'app-engine/blocks/toggle.yaml',
      'label': {'on': 'Turn off', 'off': 'Turn on'},
      'icon': {'on': 'https://example.com/icons/light-on.png', 'off': 'https://example.com/icons/light-off.png'},
      'read': 'com.example.light.ison',
      'toggle': 'com.example.light.toggle',
    },
  ];
  return app;
}

List<dynamic> children(Map<String, dynamic> app) => app['screens']['home']['layout']['children'] as List;

void main() {
  test('the predefined blocks are the repository\'s', () {
    for (final entry in predefinedBlocks.entries) {
      expect(entry.value, File('../blocks/${entry.key}.yaml').readAsStringSync(), reason: entry.key);
    }
    expect(Directory('../blocks').listSync().length, predefinedBlocks.length);
  });

  test('expands included blocks from their fields', () {
    final app = ManifestApp(exampleWithIncludes());
    expect(children(app.data), children(exampleManifest()));
  });

  test('leaves out unset fields', () {
    final app = ManifestApp({
      'screens': {
        'home': {
          'layout': {
            'children': [
              {'id': 'hello', 'include': 'app-engine/blocks/text.yaml', 'label': 'Hello, world!'},
            ],
          },
        },
      },
    });
    expect(children(app.data).single, {
      'id': 'hello',
      'block': {
        'state': {'value': 'Hello, world!'},
        'on_mount': {
          'on_result': {
            'set': {
              'value': {'bind': 'result'},
            },
          },
        },
        'component': {
          'type': 'text',
          'label': {'bind': 'state.value'},
        },
      },
    });
  });

  test('leaves unknown blocks and doesn\'t change its input', () {
    final input = exampleWithIncludes();
    (children(input).first as Map)['include'] = 'app-engine/blocks/unknown.yaml';
    final app = ManifestApp(input);
    expect(children(app.data).first['include'], 'app-engine/blocks/unknown.yaml');
    expect(children(app.data).first, isNot(contains('block')));
    expect(children(input).last, contains('include'));
  });
}
