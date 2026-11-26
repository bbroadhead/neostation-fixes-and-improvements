import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../l10n/app_locale.dart';
import '../../../services/gamepad/gamepad_navigation_manager.dart';
import '../../../services/visual_profiles/retroarch_shader_registry.dart';
import '../../../utils/gamepad_nav.dart';

class VisualShaderCatalogDialog extends StatefulWidget {
  const VisualShaderCatalogDialog({
    super.key,
    required this.registry,
    this.selectedId,
  });

  final RetroArchShaderRegistry registry;
  final String? selectedId;

  @override
  State<VisualShaderCatalogDialog> createState() =>
      _VisualShaderCatalogDialogState();
}

class _VisualShaderCatalogDialogState extends State<VisualShaderCatalogDialog> {
  static const _layer = 'visual-shader-catalog';
  static const _rowHeight = 56.0;
  final _scroll = ScrollController();
  final _searchFocus = FocusNode();
  late final GamepadNavigation _navigation;
  List<RetroArchShaderPreset>? _installed;
  List<RetroArchShaderPreset> _results = [];
  List<String> _categories = [];
  String _search = '';
  int _category = 0;
  int _selection = 0;

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateDown: () => _move(1),
      onNavigateUp: () => _move(-1),
      onNavigateLeft: () => _adjustCategory(-1),
      onNavigateRight: () => _adjustCategory(1),
      onSelectItem: () => _activate(_selection),
      onBack: _back,
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
    _load();
  }

  Future<void> _load() async {
    final installed = await widget.registry.discover();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _categories = [
        ...{
          for (final preset in installed)
            if (preset.category.isNotEmpty) preset.category,
        },
      ];
      _filter();
      final index = _results.indexWhere(
        (preset) => preset.id == widget.selectedId,
      );
      if (index >= 0) _selection = index + 3;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToSelection();
    });
  }

  void _filter() {
    final category = _category == 0 ? null : _categories[_category - 1];
    _results = [
      for (final preset in _installed ?? const <RetroArchShaderPreset>[])
        if ((category == null || preset.category == category) &&
            preset.matches(_search))
          preset,
    ];
    _selection = _selection.clamp(0, _results.length + 2);
  }

  void _move(int direction) {
    if (_searchFocus.hasFocus) return;
    setState(() {
      _selection = (_selection + direction).clamp(0, _results.length + 2);
    });
    _scrollToSelection();
  }

  void _scrollToSelection() {
    if (!_scroll.hasClients) return;
    final offset =
        _selection * _rowHeight -
        (_scroll.position.viewportDimension - _rowHeight) / 2;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
  }

  void _adjustCategory(int direction) {
    if (_selection != 1 || _categories.isEmpty || _searchFocus.hasFocus) return;
    setState(() {
      _category = (_category + direction) % (_categories.length + 1);
      _filter();
    });
  }

  void _activate(int index) {
    switch (index) {
      case 0:
        _searchFocus.requestFocus();
      case 1:
        setState(() => _selection = 1);
        _adjustCategory(1);
      case 2:
        Navigator.pop(context, '@none');
      default:
        Navigator.pop(context, _results[index - 3].id);
    }
  }

  void _back() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _navigation.dispose();
    _scroll.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final format = widget.registry.format.toUpperCase();
    return AlertDialog(
      title: Text(
        '${AppLocale.visualInstalledShaders.getString(context)} · $format',
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: _installed == null
            ? const Center(child: CircularProgressIndicator())
            : ListTileTheme(
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer,
                child: ListView.builder(
                  controller: _scroll,
                  itemExtent: _rowHeight,
                  itemCount: _results.length + 3,
                  itemBuilder: (context, index) {
                    final preset = index >= 3 ? _results[index - 3] : null;
                    final category = _category == 0
                        ? AppLocale.filterAll.getString(context)
                        : _categories[_category - 1];
                    return ListTile(
                      selected: _selection == index,
                      title: switch (index) {
                        0 => TextField(
                          focusNode: _searchFocus,
                          decoration: InputDecoration(
                            labelText: AppLocale.visualInstalledShaders
                                .getString(context),
                          ),
                          onTap: () => setState(() => _selection = 0),
                          onChanged: (search) => setState(() {
                            _search = search;
                            _selection = 0;
                            _filter();
                          }),
                          onSubmitted: (_) => _searchFocus.unfocus(),
                        ),
                        1 => Text(category),
                        2 => Text(AppLocale.systemArtNone.getString(context)),
                        _ => Text(
                          preset!.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      },
                      subtitle: preset == null
                          ? null
                          : Text(preset.id, overflow: TextOverflow.ellipsis),
                      trailing: index == 1
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: () => _activate(index),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _back,
          child: Text(AppLocale.cancel.getString(context)),
        ),
      ],
    );
  }
}
