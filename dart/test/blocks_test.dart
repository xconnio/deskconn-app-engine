import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_engine/app_engine.dart';
import 'package:app_engine/src/blocks.dart';

import 'remote_control_fixture.dart';

/// The Remote Control app as written, including app-engine's blocks.
Map<String, dynamic> remoteControlWithIncludes() {
  final app = remoteControlManifest();
  (app['screens']['home']['layout'] as Map)['children'] = [
    {
      'id': 'lock',
      'visible': {'bind': 'context.capabilities.screen'},
      'include': 'app-engine/blocks/button.yaml',
      'label': 'Lock screen',
      'icon': 'https://example.com/icons/lock.png',
      'call': 'io.xconn.deskconn.deskconnd.screen.lock',
    },
    {
      'id': 'mute',
      'visible': {'bind': 'context.capabilities.audio'},
      'include': 'app-engine/blocks/toggle.yaml',
      'label': {'on': 'Unmute', 'off': 'Mute'},
      'icon': {'on': 'https://example.com/icons/volume-off.png', 'off': 'https://example.com/icons/volume-on.png'},
      'read': 'io.xconn.deskconn.deskconnd.audio.ismuted',
      'toggle': 'io.xconn.deskconn.deskconnd.audio.togglemute',
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
    final app = ManifestApp(remoteControlWithIncludes());
    expect(children(app.data), children(remoteControlManifest()));
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
    final input = remoteControlWithIncludes();
    (children(input).first as Map)['include'] = 'app-engine/blocks/slider.yaml';
    final app = ManifestApp(input);
    expect(children(app.data).first['include'], 'app-engine/blocks/slider.yaml');
    expect(children(app.data).first, isNot(contains('block')));
    expect(children(input).last, contains('include'));
  });
}
