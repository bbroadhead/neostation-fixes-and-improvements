import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../l10n/app_locale.dart';
import '../../../models/visual_profile.dart';
import '../../../services/gamepad/gamepad_navigation_manager.dart';
import '../../../services/visual_profiles/gameplay_viewport.dart';
import '../../../services/visual_profiles/installed_border.dart';
import '../../../services/visual_profiles/retroarch_visual_session.dart';
import 'visual_shader_catalog_dialog.dart';
import 'visual_shader_parameters_dialog.dart';
import '../../../services/visual_profiles/retroarch_shader_registry.dart';
import '../../../utils/gamepad_nav.dart';
import '../../../widgets/tv_directory_picker.dart';

typedef VisualBorderResult = ({VisualProfile? profile});

class VisualBorderDialog extends StatefulWidget {
  const VisualBorderDialog({
    super.key,
    required this.system,
    required this.profile,
    this.resolutionOnly = false,
    required this.previewGeometry,
    this.shaderRegistry,
    this.shadersOnly = false,
    this.inherited,
    this.borderOrigin,
    this.shaderOrigin,
  });

  final String system;
  final VisualProfile profile;
  final bool resolutionOnly;
  final ({double aspect, int? nativeHeight})? previewGeometry;
  final RetroArchShaderRegistry? shaderRegistry;
  final bool shadersOnly;
  final VisualProfile? inherited;
  final String? borderOrigin;
  final String? shaderOrigin;

  @override
  State<VisualBorderDialog> createState() => _VisualBorderDialogState();
}

class _VisualBorderDialogState extends State<VisualBorderDialog> {
  final _layer = 'visual-border-dialog';
  late final GamepadNavigation _nav;
  List<InstalledBorder> _borders = [];
  ({PixelRect opening, Uint8List png})? _preview;
  final _rowKeys = List.generate(17, (_) => GlobalKey());
  late bool _inheritBorder = widget.profile.inheritBorder;
  late bool _inheritShader = widget.profile.inheritShader;
  late bool _shaderTab = widget.shadersOnly;
  late VisualPreset _preset = widget.profile.preset;
  late String? _shader = widget.profile.shaderId;
  late Map<String, double> _shaderParameters = widget.profile.shaderParameters;
  bool get _canEditShaderParameters =>
      widget.shaderRegistry != null && _shader != null && _shader != '@none';
  static const _shaders = <String?>[null, '@none', '@sharp', '@lcd', '@crt'];

  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  String _query = '';
  bool _favoritesOnly = false;
  bool _importing = false;
  bool _importFailed = false;
  bool _borderTouched = false;
  late final Set<String> _favorites = {...widget.profile.favoriteBorderIds};
  late int _row = widget.resolutionOnly
      ? 11
      : widget.shadersOnly
      ? 12
      : 0;
  int _index = 0;
  final _previewCache = <String, ({PixelRect opening, Uint8List png})?>{};
  bool _renderingPreview = false;
  bool _busy = true;
  bool get _fixedPlacement => _index > 0 && _borders[_index - 1].stackedDs;

  late double _size = widget.profile.size.clamp(0.25, 1.0);
  late double _x = widget.profile.horizontal;
  late double _y = widget.profile.vertical;

  ({double aspect, int? nativeHeight})? get _geometry => widget.previewGeometry;

  late final Map<String, BorderPlacement> _placements = {
    ...widget.profile.borderPlacements,
  };

  void _rememberPlacement() {
    if (_index == 0) return;
    _placements[_borders[_index - 1].id] = (
      size: _size,
      horizontal: _x,
      vertical: _y,
    );
  }

  @override
  void initState() {
    super.initState();
    _nav = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onNavigateLeft: () => _adjust(-1),
      onNavigateRight: () => _adjust(1),
      onSelectItem: _select,
      onBack: _back,
      onLeftBumper: () => _setShaderTab(false),
      onRightBumper: () => _setShaderTab(true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nav.initialize();
      GamepadNavigationManager.pushLayer(
        _layer,
        onActivate: _nav.activate,
        onDeactivate: _nav.deactivate,
      );
    });
    if (widget.resolutionOnly || widget.shadersOnly) {
      _busy = false;
    } else {
      _discover();
    }
  }

  Future<void> _discover({String? selectedId}) async {
    try {
      final borders = await InstalledBorder.discover(
        RetroArchVisualSession.flatpakConfigRoot,
        widget.system,
      );
      final aspect = _geometry?.aspect;
      final compatible = await Future.wait([
        for (final border in borders)
          if (aspect != null && border.supportsAspect(aspect))
            _validateBorder(border, aspect),
      ]);
      if (!mounted) return;
      setState(() {
        _borders = compatible.whereType<InstalledBorder>().toList();

        _index =
            _borders.indexWhere(
              (border) => border.id == (selectedId ?? widget.profile.borderId),
            ) +
            1;
        if (selectedId != null) _restorePlacement();
      });
      await _render();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<InstalledBorder?> _validateBorder(
    InstalledBorder border,
    double aspect,
  ) async {
    try {
      final preview = await border.render(
        aspect,
        display: border.stackedDs ? deckDisplay : (width: 320, height: 200),
      );
      return preview == null ? null : border;
    } catch (_) {
      return null;
    }
  }

  Future<void> _render() async {
    final selected = _index == 0 ? null : _borders[_index - 1];
    setState(() {
      _busy = selected != null && !_previewCache.containsKey(selected.id);
      _preview = selected == null ? null : _previewCache[selected.id];
    });
    if (!_busy || _renderingPreview) return;
    _renderingPreview = true;
    try {
      while (mounted && _index != 0 && _busy) {
        final border = _borders[_index - 1];
        final id = border.id;
        ({PixelRect opening, Uint8List png})? rendered;
        if (_previewCache.containsKey(id)) {
          rendered = _previewCache.remove(id);
        } else {
          try {
            rendered = await border.render(_geometry!.aspect);
          } catch (_) {
            // Leave the selection visible so the user can move to another.
          }
        }
        if (!mounted) return;
        _previewCache[id] = rendered;
        if (_previewCache.length > 6) {
          _previewCache.remove(_previewCache.keys.first);
        }
        if (_index != 0 && _borders[_index - 1].id == id) {
          setState(() {
            _busy = false;
            _preview = rendered;
          });
        }
      }
    } finally {
      _renderingPreview = false;
    }
  }

  bool get _canSave =>
      !_importing && !_busy && (_index == 0 || _preview != null);

  void _back() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _setShaderTab(bool shaderTab) {
    if (widget.resolutionOnly ||
        widget.shadersOnly ||
        _shaderTab == shaderTab) {
      return;
    }
    _searchFocus.unfocus();
    setState(() {
      _shaderTab = shaderTab;
      _row = shaderTab ? 12 : 0;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _move(int direction) {
    if (widget.resolutionOnly) {
      const rows = [11, 5, 6];
      setState(() => _row = rows[(rows.indexOf(_row) + direction + 3) % 3]);
      return;
    }
    final rows = <int>[
      if (widget.inherited != null) 16,
      ...(_shaderTab
          ? [
              12,
              if (widget.shaderRegistry != null) 14,
              if (_canEditShaderParameters) 15,
              11,
              13,
              5,
              6,
            ]
          : [
              0,
              if (!_fixedPlacement) ...[1, 2, 3, 4],
              7,
              8,
              9,
              10,
              5,
              6,
            ]),
    ];
    final current = rows.indexOf(_row);
    setState(() => _row = rows[(current + direction) % rows.length]);
    final rowContext = _rowKeys[_row].currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(rowContext);
    } else if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        _row == 0 ? 0 : _scrollController.position.maxScrollExtent,
      );
    }
  }

  void _adjust(int direction) {
    if (_fixedPlacement && _row >= 1 && _row <= 3) return;
    switch (_row) {
      case 0:
        _choose(direction);
      case 1:
        setState(() {
          _inheritBorder = false;
          _size = (_size + direction * 0.05).clamp(0.25, 1.0);
        });
      case 2:
        setState(() {
          _inheritBorder = false;
          _x = (_x + direction * 0.1).clamp(-1.0, 1.0);
        });
      case 3:
        setState(() {
          _inheritBorder = false;
          _y = (_y + direction * 0.1).clamp(-1.0, 1.0);
        });
      case 11:
        _changePreset(direction);
      case 12:
        _changeShader(direction);
    }
  }

  void _changePreset(int direction) {
    final presets = VisualPreset.values;
    setState(() {
      _inheritShader = false;
      _preset =
          presets[(_preset.index + direction + presets.length) %
              presets.length];
    });
  }

  void _changeShader(int direction) {
    final index = _shaders.indexOf(_shader);
    _selectShader(
      _shaders[(index + direction + _shaders.length) % _shaders.length],
    );
  }

  void _selectShader(String? shader) {
    if (_shader == shader && !_inheritShader) return;
    setState(() {
      _inheritShader = false;
      _shader = shader;
      _shaderParameters = const {};
    });
  }

  String get _presetLabel => (switch (_preset) {
    VisualPreset.sharpAndClean => AppLocale.visualSharpAndClean,
    VisualPreset.enhanced => AppLocale.visualEnhanced,
    VisualPreset.authentic => AppLocale.visualAuthentic,
    VisualPreset.custom => AppLocale.visualCustom,
  }).getString(context);

  String get _shaderLabel => switch (_shader) {
    '@none' => AppLocale.systemArtNone.getString(context),
    '@sharp' => 'Sharp Bilinear Simple',
    '@lcd' => 'LCD Grid v2',
    '@crt' => 'CRT Pi',
    final String custom => custom.split('/').last,
    null => AppLocale.visualPresetDefault.getString(context),
  };

  void _choose(int direction) {
    if (_importing) return;
    if (_borders.isEmpty) {
      if (!_busy && widget.profile.borderId != null) {
        setState(() {
          _inheritBorder = false;
          _borderTouched = true;
        });
      }
      return;
    }
    final candidates = [
      0,
      for (var i = 0; i < _borders.length; i++)
        if (_borders[i].matches(_query) &&
            (!_favoritesOnly || _favorites.contains(_borders[i].id)))
          i + 1,
    ];
    final current = candidates.indexOf(_index);
    final start = current < 0 ? 0 : current;
    _changeBorder(
      candidates[(start + direction + candidates.length) % candidates.length],
    );
  }

  void _changeBorder(int index) {
    setState(() {
      _inheritBorder = false;
      _borderTouched = true;
      _rememberPlacement();
      _index = index;
      _restorePlacement();
    });
    _render();
  }

  void _restorePlacement() {
    final saved = _index == 0 ? null : _placements[_borders[_index - 1].id];
    _size = saved?.size ?? 1;
    _x = saved?.horizontal ?? 0;
    _y = saved?.vertical ?? 0;
  }

  Future<void> _importBorder() async {
    if (_importing || _geometry == null) return;
    setState(() {
      _importing = true;
      _importFailed = false;
    });
    try {
      final selected = await TvDirectoryPicker.showFilePicker(
        context,
        extensions: const ['png'],
      );
      if (selected == null || !mounted) return;
      final border = await InstalledBorder.importPng(
        RetroArchVisualSession.flatpakConfigRoot,
        widget.system,
        File(selected),
      );
      if (!mounted) return;
      if (border == null) {
        setState(() => _importFailed = true);
        return;
      }
      _rememberPlacement();
      _inheritBorder = false;
      _borderTouched = true;
      await _discover(selectedId: border.id);
    } catch (_) {
      if (mounted) setState(() => _importFailed = true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _favoriteBorder() {
    if (_index == 0) return;
    final id = _borders[_index - 1].id;
    setState(() {
      if (!_favorites.remove(id)) _favorites.add(id);
    });
  }

  void _resetPlacement() {
    _inheritBorder = false;
    _size = 1;
    _x = 0;
    _y = 0;
  }

  void _select() {
    switch (_row) {
      case 0:
        _choose(1);
      case 4:
        setState(_resetPlacement);
      case 5:
        _save();
      case 6:
        _disable();
      case 7:
        _searchFocus.requestFocus();
      case 8:
        _importBorder();
      case 9:
        _favoriteBorder();
      case 10:
        setState(() => _favoritesOnly = !_favoritesOnly);
      case 11:
        _changePreset(1);
      case 12:
        _changeShader(1);
      case 13:
        _selectShader(null);
      case 14:
        _browseShaders();
      case 15:
        _editShaderParameters();
      case 16:
        _toggleInheritance();
    }
  }

  void _toggleInheritance() {
    final inherited = widget.inherited;
    if (inherited == null) return;
    setState(() {
      if (_shaderTab) {
        _inheritShader = !_inheritShader;
        if (_inheritShader) {
          _preset = inherited.preset;
          _shader = inherited.shaderId;
          _shaderParameters = inherited.shaderParameters;
        }
      } else {
        _inheritBorder = !_inheritBorder;
        if (_inheritBorder) {
          _index =
              _borders.indexWhere((border) => border.id == inherited.borderId) +
              1;
          _size = inherited.size;
          _x = inherited.horizontal;
          _y = inherited.vertical;
          _borderTouched = true;
        }
      }
    });
    if (!_shaderTab) _render();
  }

  void _disable() {
    Navigator.of(context).pop<VisualBorderResult>((profile: null));
  }

  Future<void> _browseShaders() async {
    final registry = widget.shaderRegistry;
    if (registry == null) return;
    final id = await showDialog<String>(
      context: context,
      builder: (_) =>
          VisualShaderCatalogDialog(registry: registry, selectedId: _shader),
    );
    if (!mounted || id == null) return;
    _selectShader(id);
  }

  Future<void> _editShaderParameters() async {
    if (!_canEditShaderParameters) return;
    final id = _shader!;
    final parameters = await widget.shaderRegistry!.parameters(id);
    if (!mounted || _shader != id) return;
    if (parameters.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocale.visualShaderNoParameters.getString(context)),
        ),
      );
      return;
    }
    final values = await showDialog<Map<String, double>>(
      context: context,
      builder: (_) => VisualShaderParametersDialog(
        parameters: parameters,
        values: _shaderParameters,
      ),
    );
    if (!mounted || values == null) return;
    setState(() {
      _inheritShader = false;
      _shaderParameters = values;
    });
  }

  void _save() {
    if (!_canSave) return;
    if (widget.resolutionOnly) {
      Navigator.of(context)
          .pop<VisualBorderResult>((profile: VisualProfile(preset: _preset)));
      return;
    }
    _rememberPlacement();
    Navigator.of(context).pop<VisualBorderResult>((
      profile: VisualProfile(
        preset: _preset,
        shaderId: _shader,
        shaderParameters: _shaderParameters,
        inheritBorder: _inheritBorder,
        inheritShader: _inheritShader,
        borderId: _index == 0
            ? _borderTouched
                  ? null
                  : widget.profile.borderId
            : _borders[_index - 1].id,
        size: _size,
        horizontal: _x,
        vertical: _y,
        borderPlacements: Map.unmodifiable(_placements),
        favoriteBorderIds: Set.unmodifiable(_favorites),
      ),
    ));
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _nav.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _previewView() {
    final preview = _preview;
    if (preview == null) {
      return Center(
        child: _busy
            ? const CircularProgressIndicator()
            : Text(
                (_index == 0 && _geometry != null
                        ? AppLocale.systemArtNone
                        : AppLocale.visualBorderUnavailable)
                    .getString(context),
              ),
      );
    }
    final geometry = _geometry!;
    final shaderPreview = _shaderPreviewAsset;
    final viewport = _fixedPlacement
        ? preview.opening
        : GameplayViewport.fit(
            opening: preview.opening,
            aspectRatio: geometry.aspect,
            nativeHeight: geometry.nativeHeight,
            size: _size,
            horizontal: _x,
            vertical: _y,
          );
    return Center(
      child: AspectRatio(
        aspectRatio: deckDisplay.width / deckDisplay.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / deckDisplay.width;
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                if (viewport != null)
                  Positioned(
                    left: viewport.x * scale,
                    top: viewport.y * scale,
                    width: viewport.width * scale,
                    height: viewport.height * scale,
                    child: shaderPreview == null
                        ? ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                          )
                        : Image.asset(
                            shaderPreview,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.none,
                          ),
                  ),
                Image.memory(
                  preview.png,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? get _shaderPreviewAsset {
    if (_shaderParameters.isNotEmpty) return null;
    final effect = switch (widget.shaderRegistry?.previewPreset(_shader)) {
      '@sharp' => 'sharp',
      '@lcd' => 'lcd',
      '@crt' => 'crt',
      _ => null,
    };
    final asset = switch ((widget.shaderRegistry?.format, effect)) {
      ('glsl', final effect?) => 'gl-$effect.png',
      ('slang', final effect?) => 'slang-$effect.png',
      _ when _shader == '@none' => 'raw.png',
      _ => null,
    };
    return asset == null ? null : 'assets/shader_previews/$asset';
  }

  Widget _shaderPreviewView() {
    final format = widget.shaderRegistry?.format;
    final asset = _shaderPreviewAsset;
    final unavailable = AppLocale.visualShaderPreviewUnavailable.getString(
      context,
    );
    if (asset == null) return Center(child: Text(unavailable));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, _, _) => Center(child: Text(unavailable)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            AppLocale.visualShaderStaticPreview.getString(context),
            if (_shader != '@none' && format != null) format.toUpperCase(),
          ].join(' · '),
        ),
      ],
    );
  }

  Widget _slider(
    int row,
    String label,
    double value,
    double minimum,
    ValueChanged<double> change,
  ) => ListTile(
    key: _rowKeys[row],
    selected: _row == row,
    title: Text(label),
    trailing: SizedBox(
      width: 125,
      child: Slider(
        min: minimum,
        max: 1,
        value: value,
        onChanged: _fixedPlacement
            ? null
            : (value) => setState(() {
                _row = row;
                _inheritBorder = false;
                change(value);
              }),
      ),
    ),
  );

  Widget _resolutionEditor() => AlertDialog(
    title: Text(AppLocale.visualProfiles.getString(context)),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            selected: _row == 11,
            title: Text(AppLocale.visualPreset.getString(context)),
            subtitle: Text(_presetLabel),
            onTap: () => _changePreset(1),
          ),
          ListTile(
            selected: _row == 5,
            title: Text(AppLocale.save.getString(context)),
            onTap: _save,
          ),
          ListTile(
            selected: _row == 6,
            title: Text(AppLocale.disabled.getString(context)),
            onTap: _disable,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppLocale.cancel.getString(context)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) =>
      widget.resolutionOnly ? _resolutionEditor() : _borderEditor();

  Widget _borderEditor() => AlertDialog(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocale.visualProfiles.getString(context)),
        if (!widget.shadersOnly) const SizedBox(height: 12),
        if (!widget.shadersOnly)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(AppLocale.visualBorder.getString(context)),
              ),
              ButtonSegment(
                value: true,
                label: Text(AppLocale.visualShader.getString(context)),
              ),
            ],
            selected: {_shaderTab},
            onSelectionChanged: (selection) => _setShaderTab(selection.single),
          ),
      ],
    ),
    content: SizedBox(
      width: 800,
      height: 360,
      child: Row(
        children: [
          Expanded(child: _shaderTab ? _shaderPreviewView() : _previewView()),
          const SizedBox(width: 16),
          SizedBox(
            width: 300,
            child: ListTileTheme(
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: 0.35),
              child: ListView(
                controller: _scrollController,
                children: [
                  if (widget.inherited != null)
                    SwitchListTile(
                      key: _rowKeys[16],
                      selected: _row == 16,
                      title: Text(
                        AppLocale.visualInheritDefault.getString(context),
                      ),
                      subtitle: Text(
                        (_shaderTab ? _inheritShader : _inheritBorder)
                            ? (_shaderTab
                                      ? widget.shaderOrigin
                                      : widget.borderOrigin) ??
                                  AppLocale.systemDefault.getString(context)
                            : AppLocale.visualGameOverride.getString(context),
                      ),
                      value: _shaderTab ? _inheritShader : _inheritBorder,
                      onChanged: (_) => _toggleInheritance(),
                    ),
                  if (!_shaderTab) ...[
                    ListTile(
                      key: _rowKeys[0],
                      selected: _row == 0,
                      title: Text(
                        _index == 0
                            ? AppLocale.systemArtNone.getString(context)
                            : _borders[_index - 1].zoomed
                            ? '${_borders[_index - 1].name} · '
                                  '${AppLocale.visualBorderZoomed.getString(context)}'
                            : _borders[_index - 1].name,
                      ),
                      subtitle: _index == 0
                          ? null
                          : Text(
                              _borders[_index - 1].source == 'custom'
                                  ? AppLocale.visualCustomBorder.getString(
                                      context,
                                    )
                                  : _borders[_index - 1].source,
                            ),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => _choose(-1),
                          ),
                          if (_index != 0)
                            Image(
                              image: ResizeImage.resizeIfNeeded(
                                96,
                                null,
                                _borders[_index - 1].thumbnail,
                              ),
                              width: 48,
                              height: 32,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _choose(1),
                      ),
                    ),
                    _slider(
                      1,
                      AppLocale.visualGameplaySize.getString(context),
                      _size,
                      0.25,
                      (v) => _size = v,
                    ),
                    _slider(
                      2,
                      AppLocale.visualHorizontal.getString(context),
                      _x,
                      -1,
                      (v) => _x = v,
                    ),
                    _slider(
                      3,
                      AppLocale.visualVertical.getString(context),
                      _y,
                      -1,
                      (v) => _y = v,
                    ),
                    ListTile(
                      key: _rowKeys[4],
                      selected: _row == 4,
                      enabled: !_fixedPlacement,
                      title: Text(AppLocale.reset.getString(context)),
                      onTap: () => setState(_resetPlacement),
                    ),
                    ListTile(
                      key: _rowKeys[7],
                      selected: _row == 7,
                      title: TextField(
                        focusNode: _searchFocus,
                        decoration: InputDecoration(
                          labelText: AppLocale.visualBorderSearch.getString(
                            context,
                          ),
                        ),
                        onChanged: (query) => setState(() => _query = query),
                        onSubmitted: (_) => _searchFocus.unfocus(),
                      ),
                    ),
                    ListTile(
                      key: _rowKeys[8],
                      selected: _row == 8,
                      enabled: !_importing && _geometry != null,
                      title: Text(
                        AppLocale.visualBorderImport.getString(context),
                      ),
                      subtitle: _importFailed
                          ? Text(
                              AppLocale.visualBorderUnavailable.getString(
                                context,
                              ),
                            )
                          : null,
                      onTap: _importBorder,
                    ),
                    ListTile(
                      key: _rowKeys[9],
                      selected: _row == 9,
                      enabled: _index != 0,
                      title: Text(AppLocale.favorite.getString(context)),
                      trailing: Icon(
                        _index != 0 &&
                                _favorites.contains(_borders[_index - 1].id)
                            ? Icons.star
                            : Icons.star_outline,
                      ),
                      onTap: _favoriteBorder,
                    ),
                    ListTile(
                      key: _rowKeys[10],
                      selected: _row == 10,
                      title: Text(
                        AppLocale.visualBorderFavorites.getString(context),
                      ),
                      trailing: Icon(
                        _favoritesOnly
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                      ),
                      onTap: () =>
                          setState(() => _favoritesOnly = !_favoritesOnly),
                    ),
                  ] else ...[
                    ListTile(
                      key: _rowKeys[12],
                      selected: _row == 12,
                      title: Text(AppLocale.visualShader.getString(context)),
                      subtitle: Text(_shaderLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _changeShader(1),
                    ),
                    if (widget.shaderRegistry != null)
                      ListTile(
                        key: _rowKeys[14],
                        selected: _row == 14,
                        title: Text(
                          AppLocale.visualInstalledShaders.getString(context),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _browseShaders,
                      ),
                    if (_canEditShaderParameters)
                      ListTile(
                        key: _rowKeys[15],
                        selected: _row == 15,
                        title: Text(
                          AppLocale.visualShaderParameters.getString(context),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _editShaderParameters,
                      ),
                    ListTile(
                      key: _rowKeys[11],
                      selected: _row == 11,
                      title: Text(AppLocale.visualPreset.getString(context)),
                      subtitle: Text(_presetLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _changePreset(1),
                    ),
                    ListTile(
                      key: _rowKeys[13],
                      selected: _row == 13,
                      title: Text(AppLocale.reset.getString(context)),
                      onTap: () => _selectShader(null),
                    ),
                  ],
                  ListTile(
                    key: _rowKeys[6],
                    selected: _row == 6,
                    title: Text(
                      (widget.inherited == null
                              ? AppLocale.disabled
                              : AppLocale.resetToDefault)
                          .getString(context),
                    ),
                    onTap: _disable,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        key: _rowKeys[5],
        style: _row == 5
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.tertiary,
              )
            : null,
        onPressed: _canSave ? _save : null,
        child: Text(AppLocale.save.getString(context)),
      ),
      TextButton(
        onPressed: _back,
        child: Text(AppLocale.cancel.getString(context)),
      ),
    ],
  );
}
