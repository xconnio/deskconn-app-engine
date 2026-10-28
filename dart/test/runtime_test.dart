import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_engine/app_engine.dart';

import 'remote_control_fixture.dart';

const _isMuted = 'io.xconn.deskconn.deskconnd.audio.ismuted';
const _toggleMute = 'io.xconn.deskconn.deskconnd.audio.togglemute';

/// A caller whose calls stay pending until the test answers them.
class FakeCaller {
  final List<({String procedure, Object? arg, Completer<dynamic> response})> calls = [];

  Future<dynamic> call(String procedure, Object? arg) {
    final response = Completer<dynamic>();
    calls.add((procedure: procedure, arg: arg, response: response));
    return response.future;
  }

  /// Answers the oldest unanswered call to [procedure] with [result], or fails it with [error].
  void answer(String procedure, {dynamic result, Object? error}) {
    final call = calls.firstWhere((c) => c.procedure == procedure && !c.response.isCompleted);
    error == null ? call.response.complete(result) : call.response.completeError(error);
  }

  /// Answers like [answer], then lets the caller handle the response.
  Future<void> respond(String procedure, {dynamic result, Object? error}) async {
    answer(procedure, result: result, error: error);
    await pumpEventQueue();
  }
}

/// A failed call, as a transport would report it.
class CallError implements Exception {
  CallError(this.uri);

  final String uri;
}

void main() {
  final app = ManifestApp(remoteControlManifest());
  final children = (app.entryScreen!['layout'] as Map)['children'] as List;
  Map<String, dynamic> block(String id) => (children.firstWhere((c) => c['id'] == id) as Map)['block'];

  late FakeCaller caller;
  BlockController controller(String id) => BlockController(block: block(id), context: const {}, caller: caller.call);

  setUp(() => caller = FakeCaller());

  test('reads the app', () {
    expect(app.id, 'remote-control');
    expect(app.name, 'Remote Control');
    expect(app.keyExchange, 'io.xconn.deskconn.deskconnd.remotecontrol.key.exchange');
    expect(app.entryScreen!['title'], 'Remote Control');
  });

  test('bindings, conditionals and visibility', () {
    final scope = {
      'state': {'muted': true},
    };
    expect(evaluate({'bind': 'state.muted'}, scope), true);
    expect(evaluate({'bind': 'state.missing.deeper'}, scope), isNull);
    expect(
      evaluate({
        'when': {'bind': 'state.muted'},
        'then': 'a',
        'else': 'b',
      }, scope),
      'a',
    );
    expect(
      evaluate({
        'when': {'bind': 'state.missing'},
        'then': 'a',
        'else': 'b',
      }, scope),
      'b',
    );
    expect(evaluate('literal', scope), 'literal');

    final context = {
      'capabilities': {'screen': true, 'audio': false},
    };
    expect(isVisible(null, context), true);
    expect(isVisible({'bind': 'context.capabilities.screen'}, context), true);
    expect(isVisible({'bind': 'context.capabilities.audio'}, context), false);
    expect(isVisible({'bind': 'context.capabilities.printer'}, context), false);
  });

  test('mute loads its state, then toggles', () async {
    final mute = controller('mute');
    expect(mute.eval(mute.component['label']), 'Mute');

    unawaited(mute.mount());
    expect(mute.busy, true);
    expect(caller.calls.single.procedure, _isMuted);
    await caller.respond(_isMuted, result: false);
    expect(mute.busy, false);
    expect(mute.eval(mute.component['label']), 'Mute');
    expect(mute.eval(mute.component['icon']), 'https://example.com/icons/volume-on.png');

    unawaited(mute.activate());
    expect(mute.busy, true);
    // Pressing again while the call is in flight does nothing.
    await mute.activate();
    expect(caller.calls.where((c) => c.procedure == _toggleMute), hasLength(1));
    await caller.respond(_toggleMute, result: true);
    expect(mute.state['on'], true);
    expect(mute.eval(mute.component['label']), 'Unmute');
    expect(mute.eval(mute.component['icon']), 'https://example.com/icons/volume-off.png');
  });

  test('a failed call keeps the state and shows the error', () async {
    final mute = controller('mute');
    unawaited(mute.mount());
    await caller.respond(_isMuted, result: true);

    unawaited(mute.activate());
    await caller.respond(_toggleMute, error: CallError('wamp.error.operation_failed'));
    expect(mute.busy, false);
    expect(mute.state['on'], true);
    expect(mute.error, isA<CallError>());
  });

  test('on_error gets the error uri', () async {
    final b = BlockController(
      block: {
        'state': {'failure': null},
        'on_mount': {
          'call': _isMuted,
          'on_error': {
            'set': {
              'failure': {'bind': 'error.uri'},
            },
          },
        },
        'component': {'type': 'button', 'label': 'x'},
      },
      context: const {},
      caller: caller.call,
      errorUri: (e) => (e as CallError).uri,
    );
    unawaited(b.mount());
    await caller.respond(_isMuted, error: CallError('wamp.error.no_such_procedure'));
    expect(b.state['failure'], 'wamp.error.no_such_procedure');
    expect(b.error, isNull);
  });

  test('a text block shows its label without calling', () async {
    final hello = BlockController(
      block: {
        'state': {'value': 'Hello, world!'},
        'component': {
          'type': 'text',
          'label': {'bind': 'state.value'},
        },
      },
      context: const {},
      caller: caller.call,
    );
    await hello.mount();
    expect(hello.eval(hello.component['label']), 'Hello, world!');
    expect(caller.calls, isEmpty);
  });

  test('a text block shows what it reads', () async {
    final host = BlockController(
      block: {
        'state': {'value': null},
        'on_mount': {
          'call': 'io.xconn.deskconn.deskconnd.hostname',
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
      context: const {},
      caller: caller.call,
    );
    unawaited(host.mount());
    await caller.respond('io.xconn.deskconn.deskconnd.hostname', result: 'office-pc');
    expect(host.eval(host.component['label']), 'office-pc');
  });

  test('a slider sets what it is changed to', () async {
    const read = 'io.xconn.deskconn.deskconnd.audio.volume';
    const set = 'io.xconn.deskconn.deskconnd.audio.setvolume';
    final volume = BlockController(
      block: {
        'state': {'value': null},
        'on_mount': {
          'call': read,
          'on_result': {
            'set': {
              'value': {'bind': 'result'},
            },
          },
        },
        'component': {
          'type': 'slider',
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
    );
    unawaited(volume.mount());
    await caller.respond(read, result: 30);
    expect(volume.eval(volume.component['value']), 30);

    unawaited(volume.change(55.0));
    expect(caller.calls.last.procedure, set);
    expect(caller.calls.last.arg, 55.0);
    // Changing again while the call is in flight does nothing.
    await volume.change(70.0);
    expect(caller.calls.where((c) => c.procedure == set), hasLength(1));
    await caller.respond(set, result: 55);
    expect(volume.state['value'], 55);
  });

  test('ignores responses after unmount', () async {
    final mute = controller('mute');
    unawaited(mute.mount());
    mute.dispose();
    await caller.respond(_isMuted, result: true);
    expect(mute.state['on'], false);
  });
}
