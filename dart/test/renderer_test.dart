import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_engine/app_engine.dart';

import 'remote_control_fixture.dart';
import 'runtime_test.dart' show FakeCaller;

void main() {
  final app = ManifestApp(remoteControlManifest());

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
    await tester.pumpWidget(render(caller, {'screen': true, 'audio': false}));

    expect(find.text('Lock screen'), findsOneWidget);
    expect(find.text('Mute'), findsNothing);
    expect(caller.calls, isEmpty);
  });

  testWidgets('buttons call their procedures and show their state', (tester) async {
    final caller = FakeCaller();
    await tester.pumpWidget(render(caller, {'screen': true, 'audio': true}));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    caller.answer('io.xconn.deskconn.deskconnd.audio.ismuted', result: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Mute'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    caller.answer('io.xconn.deskconn.deskconnd.audio.togglemute', result: true);
    await tester.pump();
    expect(find.text('Unmute'), findsOneWidget);

    await tester.tap(find.text('Lock screen'));
    expect(caller.calls.last.procedure, 'io.xconn.deskconn.deskconnd.screen.lock');
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
    const shutdown = 'io.xconn.deskconn.deskconnd.power.shutdown';
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
    const read = 'io.xconn.deskconn.deskconnd.cpu.usage';
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
                'label': 'Volume',
                'step': 10,
                'value': {'bind': 'state.value'},
                'on_change': {
                  'call': 'io.xconn.deskconn.deskconnd.audio.setvolume',
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
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.byType(Slider));
    expect(caller.calls.single.procedure, 'io.xconn.deskconn.deskconnd.audio.setvolume');
    expect(caller.calls.single.arg, 50.0);
    await tester.pump();
    // The dropped value shows while the call is in flight.
    expect(find.text('50'), findsOneWidget);

    caller.answer('io.xconn.deskconn.deskconnd.audio.setvolume', result: 40);
    await tester.pump();
    expect(find.text('40'), findsOneWidget);
  });
}
