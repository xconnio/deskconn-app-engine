import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_engine/app_engine.dart';

import 'example_fixture.dart';

const _isOn = 'com.example.light.ison';
const _toggleLight = 'com.example.light.toggle';

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
  final app = ManifestApp(exampleManifest());
  final children = (app.entryScreen!['layout'] as Map)['children'] as List;
  Map<String, dynamic> block(String id) => (children.firstWhere((c) => c['id'] == id) as Map)['block'];

  late FakeCaller caller;
  BlockController controller(String id) => BlockController(block: block(id), context: const {}, caller: caller.call);

  setUp(() => caller = FakeCaller());

  test('reads the app', () {
    expect(app.id, 'example');
    expect(app.name, 'Example');
    expect(app.keyExchange, 'com.example.key.exchange');
    expect(app.entryScreen!['title'], 'Example');
  });

  test('bindings, conditionals and visibility', () {
    final scope = {
      'state': {'lit': true},
    };
    expect(evaluate({'bind': 'state.lit'}, scope), true);
    expect(evaluate({'bind': 'state.missing.deeper'}, scope), isNull);
    expect(
      evaluate({
        'when': {'bind': 'state.lit'},
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
      'capabilities': {'ping': true, 'light': false},
    };
    expect(isVisible(null, context), true);
    expect(isVisible({'bind': 'context.capabilities.ping'}, context), true);
    expect(isVisible({'bind': 'context.capabilities.light'}, context), false);
    expect(isVisible({'bind': 'context.capabilities.printer'}, context), false);
  });

  test('light loads its state, then toggles', () async {
    final light = controller('light');
    expect(light.eval(light.component['label']), 'Turn on');

    unawaited(light.mount());
    expect(light.busy, true);
    expect(caller.calls.single.procedure, _isOn);
    await caller.respond(_isOn, result: false);
    expect(light.busy, false);
    expect(light.eval(light.component['label']), 'Turn on');
    expect(light.eval(light.component['icon']), 'https://example.com/icons/light-off.png');

    unawaited(light.activate());
    expect(light.busy, true);
    // Pressing again while the call is in flight does nothing.
    await light.activate();
    expect(caller.calls.where((c) => c.procedure == _toggleLight), hasLength(1));
    await caller.respond(_toggleLight, result: true);
    expect(light.state['on'], true);
    expect(light.eval(light.component['label']), 'Turn off');
    expect(light.eval(light.component['icon']), 'https://example.com/icons/light-on.png');
  });

  test('a failed call keeps the state and shows the error', () async {
    final light = controller('light');
    unawaited(light.mount());
    await caller.respond(_isOn, result: true);

    unawaited(light.activate());
    await caller.respond(_toggleLight, error: CallError('wamp.error.operation_failed'));
    expect(light.busy, false);
    expect(light.state['on'], true);
    expect(light.error, isA<CallError>());
  });

  test('on_error gets the error uri', () async {
    final b = BlockController(
      block: {
        'state': {'failure': null},
        'on_mount': {
          'call': _isOn,
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
    await caller.respond(_isOn, error: CallError('wamp.error.no_such_procedure'));
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
          'call': 'com.example.hostname',
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
    await caller.respond('com.example.hostname', result: 'office-pc');
    expect(host.eval(host.component['label']), 'office-pc');
  });

  test('a slider sets what it is changed to', () async {
    const read = 'com.example.level.get';
    const set = 'com.example.level.set';
    final level = BlockController(
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
    unawaited(level.mount());
    await caller.respond(read, result: 30);
    expect(level.eval(level.component['value']), 30);

    unawaited(level.change(55.0));
    expect(caller.calls.last.procedure, set);
    expect(caller.calls.last.arg, 55.0);
    // Changing again while the call is in flight does nothing.
    await level.change(70.0);
    expect(caller.calls.where((c) => c.procedure == set), hasLength(1));
    await caller.respond(set, result: 55);
    expect(level.state['value'], 55);
  });

  test('ignores responses after unmount', () async {
    final light = controller('light');
    unawaited(light.mount());
    light.dispose();
    await caller.respond(_isOn, result: true);
    expect(light.state['on'], false);
  });
}
