import 'package:neostation/services/visual_profiles/dolphin_visual_profile.dart';
import 'package:neostation/services/visual_profiles/retroarch_visual_session.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/core_emulator_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/models/visual_profile.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/repositories/visual_profile_repository.dart';
import 'package:neostation/services/game/game_launch_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/emulator_loader.dart';
import 'package:neostation/widgets/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings_screen/new_settings_options/visual_border_dialog.dart';

/// Per-game emulator override tab for [GameSettingsDialog].
///
/// Lists 'System Default' plus every emulator available for the game's
/// system, mirroring the behavior of the list view's settings tab.
class GameSettingsEmulatorTab extends StatefulWidget {
  final GameModel game;
  final SystemModel system;
  final bool isAllMode;
  final VoidCallback? onGameUpdated;

  const GameSettingsEmulatorTab({
    super.key,
    required this.game,
    required this.system,
    required this.isAllMode,
    this.onGameUpdated,
  });

  @override
  State<GameSettingsEmulatorTab> createState() =>
      GameSettingsEmulatorTabState();
}

class GameSettingsEmulatorTabState extends State<GameSettingsEmulatorTab> {
  static final _log = LoggerService.instance;

  List<CoreEmulatorModel> _availableEmulators = [];
  CoreEmulatorModel? _systemDefault;
  int _selectedIndex = 0;

  /// Tracks the active emulator override. Uses a sentinel to differentiate
  /// between 'not yet loaded' and 'explicit null' (system default).
  Object? _activeEmulatorId = _sentinel;
  static const Object _sentinel = Object();

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  GlobalKey _itemKey(int navIndex) =>
      _itemKeys.putIfAbsent(navIndex, () => GlobalKey());

  String? get _resolvedEmulatorId => identical(_activeEmulatorId, _sentinel)
      ? widget.game.emulatorName
      : _activeEmulatorId as String?;

  int get _visualIndex => 1 + _availableEmulators.length;

  bool get _hasVisualProfiles =>
      Platform.isLinux &&
      widget.game.romPath != null &&
      _availableEmulators.any(
        (emulator) =>
            emulator.isInstalled &&
            (!emulator.isStandalone ||
                DolphinVisualProfile.supports(emulator.uniqueId)) &&
            (_resolvedEmulatorId == null ||
                emulator.uniqueId == _resolvedEmulatorId),
      );

  int get _totalItems => _availableEmulators.isEmpty
      ? 0
      : _visualIndex + (_hasVisualProfiles ? 1 : 0);

  bool _editingProfile = false;

  Future<void> _editVisualProfile() async {
    if (_editingProfile || !_hasVisualProfiles) return;
    _editingProfile = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final repository = VisualProfileRepository(prefs);
      final system = (
        systemId: widget.system.id ?? widget.system.folderName,
        emulatorId: null,
      );
      final scope = (
        systemId: system.systemId,
        emulatorId: _resolvedEmulatorId,
      );
      final rom = widget.game.romPath!;
      final current =
          repository.read(scope, gameKey: rom) ??
          repository.read(system, gameKey: rom) ??
          repository.read(scope) ??
          repository.read(system) ??
          const VisualProfile();
      final selectedCore = scope.emulatorId == null
          ? await GameLaunchService.resolveDefaultInstalledEmulator(
              widget.system,
              availableEmulators: _availableEmulators,
            )
          : _availableEmulators
                .where((emulator) => emulator.uniqueId == scope.emulatorId)
                .firstOrNull;
      final previewGeometry =
          await RetroArchVisualSession.previewBorderGeometry(
            system: widget.system.folderName,
            coreFilename: selectedCore?.coreFilename,
            romPath: rom,
          );
      final shaderFormat = await RetroArchVisualSession.previewShaderFormat(
        coreFilename: selectedCore?.coreFilename,
        romPath: rom,
      );
      if (!mounted) return;
      final result = await showDialog<VisualBorderResult>(
        context: context,
        builder: (_) => VisualBorderDialog(
          system: widget.system.folderName,
          profile: current,
          resolutionOnly: DolphinVisualProfile.supports(selectedCore?.uniqueId),
          previewGeometry: previewGeometry,
          shaderFormat: shaderFormat,
        ),
      );
      if (result == null) return;
      final profile = result.profile;
      final saved = profile == null
          ? await repository.reset(scope, gameKey: rom)
          : await repository.save(scope, profile, gameKey: rom);
      if (!saved) throw StateError('Could not persist game visual profile');
    } catch (error) {
      _log.w('Game visual profile persistence failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocale.error.getString(context))),
        );
      }
    } finally {
      _editingProfile = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadEmulators();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEmulators() async {
    final emulators = await loadEmulatorsForSystem(widget.system);
    final systemDefault =
        await GameLaunchService.resolveDefaultInstalledEmulator(
          widget.system,
          availableEmulators: emulators,
        );
    if (!mounted) return;
    setState(() {
      _availableEmulators = emulators;
      _systemDefault = systemDefault;
    });
  }

  void moveUp() {
    if (_totalItems == 0) return;
    setState(
      () => _selectedIndex = (_selectedIndex - 1).clamp(0, _totalItems - 1),
    );
    _scrollToSelectedItem();
  }

  void moveDown() {
    if (_totalItems == 0) return;
    setState(
      () => _selectedIndex = (_selectedIndex + 1).clamp(0, _totalItems - 1),
    );
    _scrollToSelectedItem();
  }

  void trigger() {
    if (_totalItems == 0) return;
    if (_selectedIndex == 0) {
      _setEmulatorOverride(null);
      return;
    }
    if (_selectedIndex >= _visualIndex) {
      _editVisualProfile();
      return;
    }
    final emulator = _availableEmulators[_selectedIndex - 1];
    if (!emulator.isInstalled) return;
    _setEmulatorOverride(emulator);
  }

  void _scrollToSelectedItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_selectedIndex];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  /// Persists a manual emulator override for this specific game.
  Future<void> _setEmulatorOverride(CoreEmulatorModel? emulator) async {
    // Optimistic update: reflect changes in UI immediately.
    if (mounted) setState(() => _activeEmulatorId = emulator?.uniqueId);
    try {
      final targetSystemFolder =
          widget.isAllMode && widget.game.systemFolderName != null
          ? widget.game.systemFolderName!
          : widget.system.folderName;
      await GameRepository.setEmulatorOverride(
        targetSystemFolder,
        widget.game.romname,
        emulator?.uniqueId,
        emulator?.osId,
      );
      widget.onGameUpdated?.call();
    } catch (e) {
      _log.e('Emulator override persistence failed: $e');
      // Rollback: revert UI state on failure.
      if (mounted) {
        setState(() => _activeEmulatorId = widget.game.emulatorName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_availableEmulators.isEmpty) {
      return Center(
        child: Text(
          AppLocale.noEmulator.getString(context),
          style: TextStyle(
            fontSize: 12.r,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4.r, bottom: 4.r),
            child: Row(
              children: [
                Icon(
                  Symbols.sports_esports_rounded,
                  size: 12.r,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
                SizedBox(width: 4.r),
                Text(
                  AppLocale.emulator.getString(context),
                  style: TextStyle(
                    fontSize: 11.r,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Global System Default Option.
          EmulatorRow(
            key: _itemKey(0),
            isSelected: _selectedIndex == 0,
            label: [
              AppLocale.systemDefault.getString(context),
              if (_systemDefault case final emulator?) '(${emulator.name})',
            ].join(' '),
            isActive:
                _resolvedEmulatorId == null ||
                !_availableEmulators.any(
                  (e) => e.uniqueId == _resolvedEmulatorId,
                ),
            onTap: () {
              SfxService().playNavSound();
              setState(() => _selectedIndex = 0);
              _setEmulatorOverride(null);
            },
          ),
          // Individual Emulator Options.
          ..._availableEmulators.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            return EmulatorRow(
              key: _itemKey(i + 1),
              isSelected: _selectedIndex == i + 1,
              label: e.name,
              isActive: _resolvedEmulatorId == e.uniqueId,
              onTap: () {
                SfxService().playNavSound();
                setState(() => _selectedIndex = i + 1);
                _setEmulatorOverride(e);
              },
              emulator: e,
            );
          }),
          if (_hasVisualProfiles)
            SettingsRow(
              key: _itemKey(_visualIndex),
              isSelected: _selectedIndex == _visualIndex,
              icon: Symbols.aspect_ratio_rounded,
              label: AppLocale.visualProfiles.getString(context),
              subtitle: AppLocale.visualGameOverride.getString(context),
              onTap: () {
                setState(() => _selectedIndex = _visualIndex);
                _editVisualProfile();
              },
            ),
        ],
      ),
    );
  }
}
