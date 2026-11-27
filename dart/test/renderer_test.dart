import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_engine/app_engine.dart';

import 'example_fixture.dart';
import 'runtime_test.dart' show FakeCaller;

void main() {
  final app = ManifestApp(exampleManifest());

  Widget render(FakeCaller caller, Map<String, bool> capabilities) => MaterialApp(
    home: Scaffold(
      body: ManifestScreenView(
        app: app,
        screen: app.entryScreen!,
        context: {'capabilities': capabilities},
        caller: caller.call,
      ),
    ),
  );

  testWidgets('hidden blocks neither show nor call', (tester) async {
    final caller = FakeCaller();
    await tester.pumpWidget(render(caller, {'ping': true, 'light': false}));

    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);
    expect(caller.calls, isEmpty);
  });

  testWidgets('buttons call their procedures and show their state', (tester) async {
    final caller = FakeCaller();
    await tester.pumpWidget(render(caller, {'ping': true, 'light': true}));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    caller.answer('com.example.light.ison', result: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Turn on'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    caller.answer('com.example.light.toggle', result: true);
    await tester.pump();
    expect(find.text('Turn off'), findsOneWidget);

    await tester.tap(find.text('Ping'));
    expect(caller.calls.last.procedure, 'com.example.ping');
  });

  testWidgets('text blocks show their label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManifestBlockView(
            block: const {
              'state': {'value': 'Hello, world!'},
              'component': {
                'type': 'text',
                'label': {'bind': 'state.value'},
              },
            },
            context: const {},
            caller: FakeCaller().call,
          ),
        ),
      ),
    );
    expect(find.text('Hello, world!'), findsOneWidget);
  });
  testWidgets('buttons with confirm call only once confirmed', (tester) async {
    final caller = FakeCaller();
    const shutdown = 'com.example.power.shutdown';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManifestBlockView(
            block: const {
              'component': {
                'type': 'button',
                'label': 'Shut down',
                'confirm': 'Shut down the desktop?',
                'on_activate': {'call': shutdown},
              },
            },
            context: const {},
            caller: caller.call,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Shut down'));
    await tester.pumpAndSettle();
    expect(find.text('Shut down the desktop?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(caller.calls, isEmpty);

    await tester.tap(find.text('Shut down'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Shut down')));
    await tester.pump();
    expect(caller.calls.single.procedure, shutdown);
  });

  testWidgets('polls read again every few seconds without showing loading', (tester) async {
    final caller = FakeCaller();
    const read = 'com.example.cpu.usage';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManifestBlockView(
            block: const {
              'state': {'value': 'CPU'},
              'on_mount': {
                'call': read,
                'on_result': {
                  'set': {
                    'value': {'bind': 'result'},
                  },
                },
              },
              'refresh': 5,
              'component': {
                'type': 'text',
                'label': {'bind': 'state.value'},
              },
            },
            context: const {},
            caller: caller.call,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    caller.answer(read, result: '12%');
    await tester.pump();
    expect(find.text('12%'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(caller.calls, hasLength(2));
    // The last value shows while it reads again.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('12%'), findsOneWidget);
    caller.answer(read, result: '30%');
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsOneWidget);

    // It stops reading once removed.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(caller.calls, hasLength(2));
  });

  testWidgets('sliders show their value and set where they are dropped', (tester) async {
    final caller = FakeCaller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManifestBlockView(
            block: const {
              'state': {'value': 20},
              'component': {
                'type': 'slider',
                'label': 'Level',
                'step': 10,
                'value': {'bind': 'state.value'},
                'on_change': {
                  'call': 'com.example.level.set',
                  'arg': {'bind': 'value'},
                  'on_result': {
                    'set': {
                      'value': {'bind': 'result'},
                    },
                  },
                },
              },
            },
            context: const {},
            caller: caller.call,
          ),
        ),
      ),
    );
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.byType(Slider));
    expect(caller.calls.single.procedure, 'com.example.level.set');
    expect(caller.calls.single.arg, 50.0);
    await tester.pump();
    // The dropped value shows while the call is in flight.
    expect(find.text('50'), findsOneWidget);

    caller.answer('com.example.level.set', result: 40);
    await tester.pump();
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('selects show their choice and set what is picked', (tester) async {
    final caller = FakeCaller();
    const set = 'com.example.power.setmode';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManifestBlockView(
            block: const {
              'state': {'value': 'balanced'},
              'component': {
                'type': 'select',
                'label': 'Power mode',
                'options': [
                  {'value': 'saver', 'label': 'Power saver'},
                  {'value': 'balanced', 'label': 'Balanced'},
                  {'value': 'performance', 'label': 'Performance'},
                ],
                'value': {'bind': 'state.value'},
                'on_change': {
                  'call': set,
                  'arg': {'bind': 'value'},
                  'on_result': {
                    'set': {
                      'value': {'bind': 'result'},
                    },
                  },
                },
              },
            },
            context: const {},
            caller: caller.call,
          ),
        ),
      ),
    );
    expect(find.text('Power mode'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);

    await tester.tap(find.text('Balanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Performance').last);
    await tester.pumpAndSettle();
    expect(caller.calls.single.procedure, set);
    expect(caller.calls.single.arg, 'performance');
    // The picked choice shows while the call is in flight.
    expect(find.text('Performance'), findsOneWidget);

    caller.answer(set, result: 'saver');
    await tester.pumpAndSettle();
    expect(find.text('Power saver'), findsOneWidget);
  });

  testWidgets('buttons show named icons, the app\'s own icon files from the desktop, or https icons', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12Ow7f77HwAFkwLF08ImewAAAABJRU5ErkJggg==',
    );
    final loaded = <String>[];
    Future<Uint8List> loadFile(String path) async {
      loaded.add(path);
      if (path != 'icons/ping.png') throw StateError('no file $path');
      return png;
    }

    Future<void> button(String icon, {ManifestFileLoader? load}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManifestBlockView(
              key: UniqueKey(),
              block: {
                'component': {'type': 'button', 'label': 'Ping', 'icon': icon},
              },
              context: const {},
              caller: FakeCaller().call,
              loadFile: load ?? loadFile,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Image image() => tester.widget<Image>(find.byType(Image));

    await button('star');
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(loaded, isEmpty);

    await button('icons/ping.png');
    expect((image().image as MemoryImage).bytes, png);
    expect(loaded, ['icons/ping.png']);

    await button('https://example.com/ping.png');
    expect((image().image as NetworkImage).url, 'https://example.com/ping.png');

    loaded.clear();
    for (final icon in ['icons/missing.png', 'http://example.com/ping.png', 'no_such_icon', 'icons/ping.svg']) {
      await button(icon);
      expect(find.byType(Image), findsNothing, reason: icon);
      expect(find.byIcon(Icons.widgets_outlined), findsOneWidget, reason: icon);
    }
    expect(loaded, ['icons/missing.png']);
  });

  test('named icons are exactly icons/names.txt', () {
    final names = File('../icons/names.txt')
        .readAsLinesSync()
        .where((line) => !line.startsWith('#'))
        .expand((line) => line.split(' '))
        .where((name) => name.isNotEmpty);
    expect(manifestIcons.keys, orderedEquals(names));
  });
}
