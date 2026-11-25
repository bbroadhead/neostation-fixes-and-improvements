import 'package:neostation/services/visual_profiles/dolphin_visual_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/system_folder_names.dart';
import '../../../l10n/app_locale.dart';
import '../../../models/system_model.dart';
import '../../../models/visual_profile.dart';
import '../../../providers/sqlite_config_provider.dart';
import '../../../repositories/visual_profile_repository.dart';
import '../../../services/visual_profiles/retroarch_visual_session.dart';
import '../../../utils/adaptive_scroll.dart';
import '../../../utils/emulator_loader.dart';
import 'settings_title.dart';
import 'visual_border_dialog.dart';
import 'visual_profile_scope_dialog.dart';
import 'widgets/setting_value_chip.dart';
import 'widgets/settings_card_row.dart';

class VisualProfilesContent extends StatefulWidget {
  const VisualProfilesContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
  });

  final bool isContentFocused;
  final int selectedContentIndex;

  @override
  State<VisualProfilesContent> createState() => VisualProfilesContentState();
}

class VisualProfilesContentState extends State<VisualProfilesContent> {
  final _controller = ScrollController();
  final _scroller = AdaptiveScroller();
  final _keys = <GlobalKey>[];
  VisualProfileRepository? _repository;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _repository = VisualProfileRepository(prefs));
  }

  List<SystemModel> _systems(SqliteConfigProvider config) => config
      .detectedSystems
      .where(
        (system) =>
            system.id != null &&
            !SystemFolderNames.isAggregate(system.folderName) &&
            system.folderName != SystemFolderNames.search,
      )
      .toList();

  int getItemCount() => _systems(context.read<SqliteConfigProvider>()).length;

  void scrollToIndex(int index) =>
      _scroller.ensureVisibleIndex(index, keys: _keys, controller: _controller);

  Future<void> selectItem(int index) async {
    final systems = _systems(context.read<SqliteConfigProvider>());
    final repository = _repository;
    if (repository == null || _saving || index < 0 || index >= systems.length) {
      return;
    }
    final system = systems[index];
    final systemScope = (systemId: system.id!, emulatorId: null);
    setState(() => _saving = true);
    var saved = false;
    try {
      final emulators = await loadEmulatorsForSystem(system);
      if (!mounted) return;
      final cores = emulators
          .where(
            (emulator) =>
                emulator.isInstalled &&
                (!emulator.isStandalone ||
                    DolphinVisualProfile.supports(emulator.uniqueId)),
          )
          .toList();
      final selection = cores.isEmpty
          ? (emulatorId: null)
          : await showDialog<({String? emulatorId})>(
              context: context,
              builder: (_) => VisualProfileScopeDialog(cores: cores),
            );
      if (selection == null || !mounted) {
        saved = true;
        return;
      }
      final scope = (
        systemId: systemScope.systemId,
        emulatorId: selection.emulatorId,
      );
      final stored = repository.read(scope) ?? repository.read(systemScope);
      final core = cores
          .where((emulator) => emulator.uniqueId == scope.emulatorId)
          .firstOrNull;
      final geometry = await RetroArchVisualSession.previewBorderGeometry(
        system: system.folderName,
        coreFilename: core?.coreFilename,
      );
      if (!mounted) return;
      final updated = await showDialog<VisualBorderResult>(
        context: context,
        builder: (_) => VisualBorderDialog(
          system: system.folderName,
          previewGeometry: geometry,
          profile: stored ?? const VisualProfile(),
          resolutionOnly: DolphinVisualProfile.supports(scope.emulatorId),
        ),
      );
      final profile = updated?.profile;
      saved =
          updated == null ||
          (profile == null
              ? await repository.reset(scope)
              : await repository.save(scope, profile));
    } catch (_) {
      await _load();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (!saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocale.error.getString(context))),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final systems = _systems(context.watch<SqliteConfigProvider>());
    while (_keys.length < systems.length) {
      _keys.add(GlobalKey());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsTitle(
          title: AppLocale.visualProfiles.getString(context),
          subtitle: AppLocale.visualProfilesSubtitle.getString(context),
        ),
        SizedBox(height: 12.r),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            itemCount: systems.length,
            itemBuilder: (context, index) {
              final system = systems[index];
              final scope = (systemId: system.id!, emulatorId: null);
              final profile = _repository?.read(scope);
              final preset = switch (profile?.preset) {
                VisualPreset.sharpAndClean => AppLocale.visualSharpAndClean,
                VisualPreset.enhanced => AppLocale.visualEnhanced,
                VisualPreset.authentic => AppLocale.visualAuthentic,
                VisualPreset.custom => AppLocale.visualCustom,
                null => AppLocale.disabled,
              };
              return SettingsCardRow(
                key: _keys[index],
                icon: Symbols.aspect_ratio_rounded,
                title: system.realName,
                subtitle: system.folderName,
                selected:
                    widget.isContentFocused &&
                    index == widget.selectedContentIndex,
                disabled: _repository == null || _saving,
                onTap: () => selectItem(index),
                trailing: SettingValueChip(
                  text:
                      profile?.borderId?.split('/').last.split('--').first ??
                      preset.getString(context),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
