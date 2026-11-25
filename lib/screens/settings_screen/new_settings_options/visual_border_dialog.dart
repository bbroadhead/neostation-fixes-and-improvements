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
import '../../../utils/gamepad_nav.dart';
import '../../../widgets/tv_directory_picker.dart';

typedef VisualBorderResult = ({VisualProfile? profile});

class VisualBorderDialog extends StatefulWidget {
  const VisualBorderDialog({
    super.key,
    required this.system,
    required this.profile,
    this.resolutionOnly = false,
    this.previewGeometry,
  });

  final String system;
  final VisualProfile profile;
  final bool resolutionOnly;
  final ({double aspect, int? nativeHeight})? previewGeometry;

  @override
  State<VisualBorderDialog> createState() => _VisualBorderDialogState();
}

class _VisualBorderDialogState extends State<VisualBorderDialog> {
  final _layer = 'visual-border-dialog';
  late final GamepadNavigation _nav;
  List<InstalledBorder> _borders = [];
  ({PixelRect opening, Uint8List png})? _preview;
  final _rowKeys = List.generate(13, (_) => GlobalKey());
  late VisualPreset _preset = widget.profile.preset;
  late String? _shader = widget.profile.shaderId;
  static const _shaders = <String?>[null, '@sharp', '@lcd', '@crt'];

  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  String _query = '';
  bool _favoritesOnly = false;
  bool _importing = false;
  bool _importFailed = false;
  late final Set<String> _favorites = {...widget.profile.favoriteBorderIds};
  late int _row = widget.resolutionOnly ? 11 : 0;
  int _index = 0;
  int _loadRevision = 0;
  bool _busy = true;
  bool get _fixedPlacement => _index > 0 && _borders[_index - 1].stackedDs;

  late double _size = widget.profile.size.clamp(0.25, 1.0);
  late double _x = widget.profile.horizontal;
  late double _y = widget.profile.vertical;

  ({double aspect, int? nativeHeight})? get _geometry =>
      widget.previewGeometry ?? InstalledBorder.geometry(widget.system);

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
      onBack: () => Navigator.of(context).pop(),
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
    if (widget.resolutionOnly) {
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
    if (border.configuredOpening == null) return border;
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
    final revision = ++_loadRevision;
    setState(() {
      _busy = _index != 0;
      _preview = null;
    });
    if (_index == 0) return;
    ({PixelRect opening, Uint8List png})? rendered;
    try {
      rendered = await _borders[_index - 1].render(_geometry!.aspect);
    } catch (_) {
      // Keep the selection visible so the user can move to another border.
    }
    if (!mounted || revision != _loadRevision) return;
    setState(() {
      _busy = false;
      _preview = rendered;
    });
  }

  bool get _canSave =>
      !_importing && !_busy && (_index == 0 || _preview != null);

  void _move(int direction) {
    if (widget.resolutionOnly) {
      const rows = [11, 5, 6];
      setState(() => _row = rows[(rows.indexOf(_row) + direction + 3) % 3]);
      return;
    }
    final count = _rowKeys.length;
    setState(() => _row = (_row + direction + count) % count);
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
        setState(() => _size = (_size + direction * 0.05).clamp(0.25, 1.0));
      case 2:
        setState(() => _x = (_x + direction * 0.1).clamp(-1.0, 1.0));
      case 3:
        setState(() => _y = (_y + direction * 0.1).clamp(-1.0, 1.0));
      case 11:
        _changePreset(direction);
      case 12:
        _changeShader(direction);
    }
  }

  void _changePreset(int direction) {
    final presets = VisualPreset.values;
    setState(() {
      _preset =
          presets[(_preset.index + direction + presets.length) %
              presets.length];
    });
  }

  void _changeShader(int direction) {
    setState(() {
      final index = _shaders.indexOf(_shader);
      _shader =
          _shaders[(index + direction + _shaders.length) % _shaders.length];
    });
  }

  String get _presetLabel => (switch (_preset) {
    VisualPreset.sharpAndClean => AppLocale.visualSharpAndClean,
    VisualPreset.enhanced => AppLocale.visualEnhanced,
    VisualPreset.authentic => AppLocale.visualAuthentic,
    VisualPreset.custom => AppLocale.visualCustom,
  }).getString(context);

  String get _shaderLabel => switch (_shader) {
    '@sharp' => 'Sharp Bilinear',
    '@lcd' => 'LCD Grid',
    '@crt' => 'CRT Pi',
    final String custom => custom.split('/').last,
    null => AppLocale.visualPresetDefault.getString(context),
  };

  void _choose(int direction) {
    if (_borders.isEmpty || _importing) return;
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
    if (_importing || InstalledBorder.geometry(widget.system) == null) return;
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
    }
  }

  void _disable() {
    Navigator.of(context).pop<VisualBorderResult>((profile: null));
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
        borderId: _index == 0 ? null : _borders[_index - 1].id,
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
                (_index == 0
                        ? AppLocale.systemArtNone
                        : AppLocale.visualBorderUnavailable)
                    .getString(context),
              ),
      );
    }
    final geometry = _geometry!;
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
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.primaryContainer,
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
    title: Text(AppLocale.visualProfiles.getString(context)),
    content: SizedBox(
      width: 800,
      height: 360,
      child: Row(
        children: [
          Expanded(child: _previewView()),
          const SizedBox(width: 16),
          SizedBox(
            width: 300,
            child: ListView(
              controller: _scrollController,
              children: [
                ListTile(
                  key: _rowKeys[0],
                  selected: _row == 0,
                  title: Text(
                    _index == 0
                        ? AppLocale.systemArtNone.getString(context)
                        : _borders[_index - 1].name,
                  ),
                  subtitle: _index == 0
                      ? null
                      : Text(
                          _borders[_index - 1].source == 'custom'
                              ? AppLocale.visualCustomBorder.getString(context)
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
                        Image.file(
                          _borders[_index - 1].image,
                          width: 48,
                          height: 32,
                          cacheWidth: 96,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
                  title: Text(AppLocale.reset.getString(context)),
                  onTap: () => setState(_resetPlacement),
                ),
                ListTile(
                  key: _rowKeys[5],
                  selected: _row == 5,
                  enabled: _canSave,
                  title: Text(AppLocale.save.getString(context)),
                  onTap: _canSave ? _save : null,
                ),
                ListTile(
                  key: _rowKeys[6],
                  selected: _row == 6,
                  title: Text(AppLocale.disabled.getString(context)),
                  onTap: _disable,
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
                  enabled:
                      !_importing &&
                      InstalledBorder.geometry(widget.system) != null,
                  title: Text(AppLocale.visualBorderImport.getString(context)),
                  subtitle: _importFailed
                      ? Text(
                          AppLocale.visualBorderUnavailable.getString(context),
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
                    _index != 0 && _favorites.contains(_borders[_index - 1].id)
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
                  onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
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
                  key: _rowKeys[12],
                  selected: _row == 12,
                  title: Text(AppLocale.visualShader.getString(context)),
                  subtitle: Text(_shaderLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changeShader(1),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(AppLocale.cancel.getString(context)),
      ),
    ],
  );
}
