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
