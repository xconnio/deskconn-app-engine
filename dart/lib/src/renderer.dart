import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'icons.dart';
import 'runtime.dart';

/// Renders a manifest app's [screen]: its layout, and a block for each visible child.
class ManifestScreenView extends StatelessWidget {
  const ManifestScreenView({
    super.key,
    required this.app,
    required this.screen,
    required this.context,
    required this.caller,
    this.errorUri,
    this.loadFile,
  });

  final ManifestApp app;
  final Map<String, dynamic> screen;

  /// What `context.*` bindings read, e.g. `capabilities`.
  final Map<String, dynamic> context;
  final ManifestCaller caller;
  final ErrorUri? errorUri;

  /// Loads the app's own icon files; without it, only https icons show.
  final ManifestFileLoader? loadFile;

  @override
  Widget build(BuildContext buildContext) {
    final layout = (screen['layout'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (layout['type'] != 'grid') return _Unsupported('layout ${layout['type']}');

    final children = [
      for (final child in (layout['children'] as List? ?? const []).whereType<Map>())
        if (isVisible(child['visible'], context)) child.cast<String, dynamic>(),
    ];
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: (layout['columns'] as num?)?.toInt().clamp(1, 6) ?? 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        for (final child in children)
          ManifestBlockView(
            // Keyed by id so a block keeps its state while others show or hide.
            key: ValueKey(child['id']),
            block: (child['block'] as Map?)?.cast<String, dynamic>() ?? const {},
            context: context,
            caller: caller,
            errorUri: errorUri,
            loadFile: loadFile,
          ),
      ],
    );
  }
}

/// A mounted block. It mounts when built and unmounts when removed.
class ManifestBlockView extends StatefulWidget {
  const ManifestBlockView({
    super.key,
    required this.block,
    required this.context,
    required this.caller,
    this.errorUri,
    this.loadFile,
  });

  final Map<String, dynamic> block;
  final Map<String, dynamic> context;
  final ManifestCaller caller;
  final ErrorUri? errorUri;
  final ManifestFileLoader? loadFile;

  @override
  State<ManifestBlockView> createState() => _ManifestBlockViewState();
}

class _ManifestBlockViewState extends State<ManifestBlockView> {
  late final BlockController _controller = BlockController(
    block: widget.block,
    context: widget.context,
    caller: widget.caller,
    errorUri: widget.errorUri ?? (error) => error.toString(),
  );

  @override
  void initState() {
    super.initState();
    _controller.mount();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final component = _controller.component;
        return switch (component['type']) {
          'button' => _ManifestButton(controller: _controller, component: component, loadFile: widget.loadFile),
          'text' => _ManifestText(controller: _controller, component: component),
          'slider' => _ManifestSlider(controller: _controller, component: component),
          'select' => _ManifestSelect(controller: _controller, component: component),
          final type => _Unsupported('component $type'),
        };
      },
    );
  }
}

class _ManifestButton extends StatelessWidget {
  const _ManifestButton({required this.controller, required this.component, this.loadFile});

  final BlockController controller;
  final Map<String, dynamic> component;
  final ManifestFileLoader? loadFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = controller.eval(component['label'])?.toString() ?? '';
    final icon = controller.eval(component['icon'])?.toString();
    final question = controller.eval(component['confirm'])?.toString();
    final error = controller.error;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: controller.busy
            ? null
            : question == null
            ? controller.activate
            : () async {
                if (await _confirm(context, question, label)) controller.activate();
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 40,
                child: controller.busy
                    ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 3))
                    : ManifestIcon(icon: icon, loadFile: loadFile),
              ),
              const SizedBox(height: 12),
              Text(label, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks [question] in a dialog, returning whether the user confirmed with [action].
Future<bool> _confirm(BuildContext context, String question, String action) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ManifestText extends StatelessWidget {
  const _ManifestText({required this.controller, required this.component});

  final BlockController controller;
  final Map<String, dynamic> component;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = controller.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: controller.busy && !controller.loaded
              ? const CircularProgressIndicator(strokeWidth: 3)
              : Text(
                  error?.toString() ?? controller.eval(component['label'])?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: error == null
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
        ),
      ),
    );
  }
}

class _ManifestSlider extends StatefulWidget {
  const _ManifestSlider({required this.controller, required this.component});

  final BlockController controller;
  final Map<String, dynamic> component;

  @override
  State<_ManifestSlider> createState() => _ManifestSliderState();
}

class _ManifestSliderState extends State<_ManifestSlider> {
  /// The value being dragged, held until its change call returns.
  double? _dragging;

  double? _number(String key) => (widget.controller.eval(widget.component[key]) as num?)?.toDouble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final min = _number('min') ?? 0;
    final max = _number('max') ?? 100;
    if (max <= min) return const _Unsupported('slider range');
    final step = _number('step');
    final value = (_dragging ?? _number('value') ?? min).clamp(min, max);
    final error = controller.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              controller.eval(widget.component['label'])?.toString() ?? '',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1),
              style: theme.textTheme.titleMedium,
            ),
            Slider(
              min: min,
              max: max,
              divisions: step != null && step > 0 ? ((max - min) / step).round() : null,
              value: value,
              onChanged: controller.busy ? null : (v) => setState(() => _dragging = v),
              onChangeEnd: controller.busy
                  ? null
                  : (v) => controller.change(v).whenComplete(() {
                      if (mounted) setState(() => _dragging = null);
                    }),
            ),
            if (error != null)
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

class _ManifestSelect extends StatefulWidget {
  const _ManifestSelect({required this.controller, required this.component});

  final BlockController controller;
  final Map<String, dynamic> component;

  @override
  State<_ManifestSelect> createState() => _ManifestSelectState();
}

class _ManifestSelectState extends State<_ManifestSelect> {
  /// The index picked, held until its change call returns.
  int? _picking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final options = [
      for (final option in (controller.eval(widget.component['options']) as List? ?? const []).whereType<Map>())
        (value: option['value'], label: (option['label'] ?? option['value'])?.toString() ?? ''),
    ];
    final current = options.indexWhere((o) => o.value == controller.eval(widget.component['value']));
    final error = controller.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              controller.eval(widget.component['label'])?.toString() ?? '',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            DropdownButton<int>(
              isExpanded: true,
              value: _picking ?? (current < 0 ? null : current),
              items: [
                for (final (i, option) in options.indexed)
                  DropdownMenuItem(
                    value: i,
                    child: Text(option.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: controller.busy
                  ? null
                  : (i) {
                      if (i == null || i == current) return;
                      setState(() => _picking = i);
                      controller.change(options[i].value).whenComplete(() {
                        if (mounted) setState(() => _picking = null);
                      });
                    },
            ),
            if (error != null)
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a manifest [icon]: a name from [manifestIcons], such as play_arrow; an https URL; or
/// one of the app's own PNG files, by its path from the app's directory, loaded from the
/// desktop with [loadFile]. Anything else, or an image that fails to load, shows [fallback].
class ManifestIcon extends StatefulWidget {
  const ManifestIcon({
    super.key,
    required this.icon,
    this.loadFile,
    this.size = 32,
    this.fallback = const Icon(Icons.widgets_outlined, size: 32),
  });

  final String? icon;
  final ManifestFileLoader? loadFile;
  final double size;
  final Widget fallback;

  @override
  State<ManifestIcon> createState() => _ManifestIconState();
}

class _ManifestIconState extends State<ManifestIcon> {
  /// The app file being shown and its load, kept while [ManifestIcon.icon] stays the same.
  String? _file;
  Future<Uint8List>? _loading;

  Future<Uint8List>? _load(String? icon) {
    final loadFile = widget.loadFile;
    if (icon == null || loadFile == null || icon.contains('://') || !icon.endsWith('.png')) return null;
    if (icon != _file) {
      _file = icon;
      _loading = loadFile(icon);
    }
    return _loading;
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    final fallback = widget.fallback;
    final named = manifestIcons[icon];
    if (named != null) return Icon(named, size: widget.size);
    if (icon != null && icon.startsWith('https://')) {
      return Image.network(icon, width: widget.size, height: widget.size, errorBuilder: (_, _, _) => fallback);
    }
    final loading = _load(icon);
    if (loading == null) return fallback;
    return FutureBuilder(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) return fallback;
        final data = snapshot.data;
        if (data == null) return SizedBox.square(dimension: widget.size);
        return Image.memory(
          data,
          width: widget.size,
          height: widget.size,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported(this.what);

  final String what;

  @override
  Widget build(BuildContext context) => Center(child: Text('Unsupported $what'));
}
