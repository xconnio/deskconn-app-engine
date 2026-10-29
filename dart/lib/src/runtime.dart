import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import 'blocks.dart';

/// Calls [procedure] on the desktop with an optional [arg] and returns its decoded result.
typedef ManifestCaller = Future<dynamic> Function(String procedure, Object? arg);

/// Returns the error URI of a failed call, which `on_error` reads as `error.uri`.
typedef ErrorUri = String Function(Object error);

String _errorString(Object error) => error.toString();

/// A manifest app as deskconn-userd's manifest.get returns it: app.yaml with its screens
/// resolved to a map by id, and each include of the app's own files replaced by the included
/// block under `block`. Includes of app-engine's blocks are expanded here (see [expandBlocks]).
class ManifestApp {
  ManifestApp(Map<String, dynamic> data) : data = expandBlocks(data);

  final Map<String, dynamic> data;

  Map<String, dynamic> get _app => (data['app'] as Map?)?.cast<String, dynamic>() ?? const {};

  String get id => _app['id']?.toString() ?? '';

  String get name => _app['name']?.toString() ?? id;

  String get keyExchange => (data['api'] as Map?)?['key_exchange']?.toString() ?? '';

  Map<String, dynamic>? screen(String id) => (data['screens'] as Map?)?[id] as Map<String, dynamic>?;

  Map<String, dynamic>? get entryScreen => screen(data['entry_screen']?.toString() ?? '');
}

const _blocksDirectory = 'app-engine/blocks/';

/// Returns [app] with each `include: app-engine/blocks/<name>.yaml` replaced by that block
/// under `block`, filled in from the including map's other fields: each `{param: <field>}`
/// in the block takes the field's value at that dotted path, and is left out where it isn't
/// set. The including map keeps only its `id` and `visible`. Unknown blocks are left as they
/// are, for the renderer to show as unsupported.
Map<String, dynamic> expandBlocks(Map<String, dynamic> app) {
  final copy = jsonDecode(jsonEncode(app)) as Map<String, dynamic>;
  _expand(copy);
  return copy;
}

void _expand(dynamic node) {
  if (node is List) {
    node.forEach(_expand);
    return;
  }
  if (node is! Map<String, dynamic>) return;

  final include = node['include'];
  final name = include is String && include.startsWith(_blocksDirectory)
      ? include.substring(_blocksDirectory.length).replaceAll(RegExp(r'\.yaml$'), '')
      : null;
  final template = predefinedBlocks[name];
  if (template != null) {
    final fields = {
      for (final entry in node.entries)
        if (entry.key != 'id' && entry.key != 'visible' && entry.key != 'include') entry.key: entry.value,
    };
    node.removeWhere((key, _) => key != 'id' && key != 'visible');
    node['block'] = _fill(jsonDecode(jsonEncode(loadYaml(template))), fields).value;
    return;
  }
  node.values.forEach(_expand);
}

/// Fills [node]'s `{param: <field>}`s from [fields], returning whether to keep it.
({dynamic value, bool keep}) _fill(dynamic node, Map<String, dynamic> fields) {
  if (node is Map<String, dynamic>) {
    final field = node['param'];
    if (node.length == 1 && field is String) {
      dynamic value = fields;
      for (final part in field.split('.')) {
        if (value is! Map || !value.containsKey(part)) return (value: null, keep: false);
        value = value[part];
      }
      return (value: value, keep: true);
    }
    for (final key in node.keys.toList()) {
      final filled = _fill(node[key], fields);
      filled.keep ? node[key] = filled.value : node.remove(key);
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      node[i] = _fill(node[i], fields).value;
    }
  }
  return (value: node, keep: true);
}

/// Reads a dotted [path] such as `state.muted` from [scope]. Missing paths read null.
dynamic readPath(Map<String, dynamic> scope, String path) {
  dynamic node = scope;
  for (final part in path.split('.')) {
    if (node is! Map) return null;
    node = node[part];
  }
  return node;
}

/// Evaluates a manifest value: `{bind: path}` reads [scope], `{when, then, else}` picks a
/// branch (anything but true selects else), and anything else is a literal.
dynamic evaluate(dynamic value, Map<String, dynamic> scope) {
  if (value is Map) {
    if (value.containsKey('bind')) return readPath(scope, value['bind'].toString());
    if (value.containsKey('when')) {
      return evaluate(evaluate(value['when'], scope) == true ? value['then'] : value['else'], scope);
    }
  }
  return value;
}

/// Whether a child with [visible] shows, given the renderer's [context].
bool isVisible(dynamic visible, Map<String, dynamic> context) =>
    visible == null || evaluate(visible, {'context': context}) == true;

/// A mounted block: its state, and the actions of its `on_mount` and component.
class BlockController extends ChangeNotifier {
  BlockController({
    required Map<String, dynamic> block,
    required this.context,
    required this.caller,
    this.errorUri = _errorString,
  }) : _block = block,
       state = Map<String, dynamic>.of((block['state'] as Map?)?.cast<String, dynamic>() ?? const {});

  final Map<String, dynamic> _block;
  final Map<String, dynamic> context;
  final ManifestCaller caller;
  final ErrorUri errorUri;
  final Map<String, dynamic> state;

  /// Whether a call is in flight. The renderer shows loading and disables the block.
  bool busy = false;

  /// The last failed call that had no on_error, shown by the renderer.
  Object? error;

  bool _disposed = false;

  Map<String, dynamic> get component => (_block['component'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic> get _scope => {'state': state, 'context': context};

  /// Evaluates [value] against the block's state and context.
  dynamic eval(dynamic value) => evaluate(value, _scope);

  /// Runs `on_mount`, if any.
  Future<void> mount() => _run(_block['on_mount'], _scope);

  /// Runs the component's `on_activate`, unless a call is already in flight.
  Future<void> activate() async {
    if (busy) return;
    await _run(component['on_activate'], _scope);
  }

  Future<void> _run(dynamic action, Map<String, dynamic> scope) async {
    if (action is! Map || _disposed) return;

    final set = action['set'];
    if (set is Map) {
      for (final entry in set.entries) {
        state[entry.key.toString()] = evaluate(entry.value, scope);
      }
      _notify();
    }

    final procedure = action['call'];
    if (procedure is! String) return;

    busy = true;
    error = null;
    _notify();
    try {
      final result = await caller(procedure, action.containsKey('arg') ? evaluate(action['arg'], scope) : null);
      if (_disposed) return;
      busy = false;
      await _run(action['on_result'], {...scope, 'result': result});
    } catch (e) {
      if (_disposed) return;
      busy = false;
      if (action['on_error'] is Map) {
        await _run(action['on_error'], {
          ...scope,
          'error': {'uri': errorUri(e)},
        });
      } else {
        error = e;
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
