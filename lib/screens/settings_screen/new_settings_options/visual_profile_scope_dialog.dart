import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../l10n/app_locale.dart';
import '../../../models/core_emulator_model.dart';
import '../../../services/gamepad/gamepad_navigation_manager.dart';
import '../../../utils/gamepad_nav.dart';

class VisualProfileScopeDialog extends StatefulWidget {
  const VisualProfileScopeDialog({super.key, required this.cores});

  final List<CoreEmulatorModel> cores;

  @override
  State<VisualProfileScopeDialog> createState() =>
      _VisualProfileScopeDialogState();
}

class _VisualProfileScopeDialogState extends State<VisualProfileScopeDialog> {
  static const _layer = 'visual-profile-scope';
  final _scroll = ScrollController();
  late final GamepadNavigation _navigation;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onSelectItem: () => _select(_index),
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

  void _move(int amount) {
    setState(() => _index = (_index + amount).clamp(0, widget.cores.length));
    if (!_scroll.hasClients) return;
    final offset = _index * 56.0 - _scroll.position.viewportDimension / 2 + 28;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
  }

  void _select(int index) => Navigator.pop(context, (
    emulatorId: index == 0 ? null : widget.cores[index - 1].uniqueId,
  ));

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _navigation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AppLocale.emulator.getString(context)),
    content: SizedBox(
      width: 440,
      height: 280,
      child: ListView.builder(
        controller: _scroll,
        itemExtent: 56,
        itemCount: widget.cores.length + 1,
        itemBuilder: (context, index) => ListTile(
          selected: index == _index,
          title: Text(
            index == 0
                ? AppLocale.systemDefault.getString(context)
                : widget.cores[index - 1].name,
          ),
          onTap: () => _select(index),
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
