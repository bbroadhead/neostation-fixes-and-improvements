import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../l10n/app_locale.dart';
import '../../../services/gamepad/gamepad_navigation_manager.dart';
import '../../../services/visual_profiles/retroarch_shader_registry.dart';
import '../../../utils/gamepad_nav.dart';

class VisualShaderParametersDialog extends StatefulWidget {
  const VisualShaderParametersDialog({
    super.key,
    required this.parameters,
    required this.values,
  });

  final List<RetroArchShaderParameter> parameters;
  final Map<String, double> values;

  @override
  State<VisualShaderParametersDialog> createState() =>
      _VisualShaderParametersDialogState();
}

class _VisualShaderParametersDialogState
    extends State<VisualShaderParametersDialog> {
  static const _layer = 'visual-shader-parameters';
  static const _rowHeight = 64.0;
  final _scroll = ScrollController();
  late final _values = {...widget.values};
  late final GamepadNavigation _navigation;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onNavigateLeft: () => _adjust(-1),
      onNavigateRight: () => _adjust(1),
      onSelectItem: () {
        if (_index == widget.parameters.length) _reset();
        if (_index == widget.parameters.length + 1) _save();
      },
      onBack: () => Navigator.pop(context),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigation.initialize();
      GamepadNavigationManager.pushLayer(
        _layer,
        onActivate: _navigation.activate,
        onDeactivate: _navigation.deactivate,
      );
    });
  }

  void _move(int direction) {
    setState(() {
      _index = (_index + direction).clamp(0, widget.parameters.length + 1);
    });
    if (!_scroll.hasClients) return;
    final offset =
        _index * _rowHeight -
        (_scroll.position.viewportDimension - _rowHeight) / 2;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
  }

  double _value(RetroArchShaderParameter parameter) =>
      (_values[parameter.id] ?? parameter.initial).clamp(
        parameter.minimum,
        parameter.maximum,
      );

  void _setValue(RetroArchShaderParameter parameter, double value) {
    final bounded = value.clamp(parameter.minimum, parameter.maximum);
    setState(() {
      if ((bounded - parameter.initial).abs() < 0.000001) {
        _values.remove(parameter.id);
      } else {
        _values[parameter.id] = bounded;
      }
    });
  }

  void _adjust(int direction) {
    if (_index >= widget.parameters.length) return;
    final parameter = widget.parameters[_index];
    _setValue(parameter, _value(parameter) + parameter.step * direction);
  }

  void _reset() => setState(_values.clear);

  void _save() =>
      Navigator.pop(context, Map<String, double>.unmodifiable(_values));

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _navigation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AppLocale.visualShaderParameters.getString(context)),
    content: SizedBox(
      width: 560,
      height: 360,
      child: ListTileTheme(
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        child: ListView.builder(
          controller: _scroll,
          itemExtent: _rowHeight,
          itemCount: widget.parameters.length + 2,
          itemBuilder: (context, index) {
            final count = widget.parameters.length;
            if (index >= count) {
              final reset = index == count;
              return ListTile(
                selected: _index == index,
                title: Text(
                  (reset ? AppLocale.reset : AppLocale.save).getString(context),
                ),
                onTap: reset ? _reset : _save,
              );
            }
            final parameter = widget.parameters[index];
            final value = _value(parameter);
            return ListTile(
              selected: _index == index,
              title: Text(parameter.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(value.toStringAsFixed(3)),
              trailing: SizedBox(
                width: 205,
                child: Slider(
                  min: parameter.minimum,
                  max: parameter.maximum,
                  divisions:
                      ((parameter.maximum - parameter.minimum) / parameter.step)
                          .round()
                          .clamp(1, 1000),
                  value: value,
                  onChanged: (value) => _setValue(parameter, value),
                ),
              ),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppLocale.cancel.getString(context)),
      ),
    ],
  );
}
