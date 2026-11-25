import 'dart:io';

import '../../models/game_model.dart';
import '../../models/ra_compatibility.dart';
import '../../models/system_model.dart';
import '../../repositories/emulator_repository.dart';
import '../../repositories/retro_achievements_repository.dart';
import '../../utils/ra_coverage.dart';
import '../retro_achievements_service.dart';
import '../linux_emulator_discovery.dart';
import '../visual_profiles/retroarch_visual_session.dart';
import 'game_launch_service.dart';

enum RaLaunchReadiness { verified, warning, unsupported, unknown }

class RaLaunchReadinessService {
  static Future<RaLaunchReadiness> check(
    GameModel game,
    SystemModel system, {
    required String username,
    required String apiKey,
  }) async {
    if (!isRaSupportedSystem(game.systemRaId ?? system.raId)) {
      return RaLaunchReadiness.unsupported;
    }
    final path = game.romPath;
    final systemId = system.id;
    if (path == null || systemId == null) return RaLaunchReadiness.unknown;
    try {
      final compatibility =
          await RetroAchievementsRepository.getRomCompatibility(path);
      if (compatibility.status == RaCompatibilityStatus.noAchievementSet) {
        return RaLaunchReadiness.unsupported;
      }
      if (compatibility.status == RaCompatibilityStatus.differentRomRequired) {
        return RaLaunchReadiness.warning;
      }
      if (compatibility.status != RaCompatibilityStatus.supported) {
        return RaLaunchReadiness.unknown;
      }
      final emulatorId = await GameLaunchService.resolveLaunchEmulatorId(
        system,
        game,
      );
      if (emulatorId == null) return RaLaunchReadiness.unknown;
      final emulators = await EmulatorRepository.getEmulatorsForSystemCurrentOs(
        systemId,
      );
      final emulator = emulators
          .where((candidate) => candidate.uniqueId == emulatorId)
          .firstOrNull;
      if (emulator == null) return RaLaunchReadiness.unknown;
      if (!emulator.isretroAchievementsCompatible) {
        return RaLaunchReadiness.unsupported;
      }
      if (username.isEmpty || apiKey.isEmpty) return RaLaunchReadiness.warning;
      final connection = await RetroAchievementsService.probeConnection(
        username,
        apiKey,
      );
      if (connection != RaConnectionStatus.available) {
        return RaLaunchReadiness.warning;
      }
      if (!Platform.isLinux || !emulator.isRetroArch) {
        return RaLaunchReadiness.unknown;
      }
      final core = emulator.coreFilename;
      if (core == null) return RaLaunchReadiness.unknown;
      final detected = await EmulatorRepository.getUserDetectedEmulators();
      final selected = detected['RetroArch']?.path;
      final executable = selected != null && await File(selected).exists()
          ? selected
          : await LinuxEmulatorDiscovery.resolveExecutable(
              executable: 'retroarch',
              flatpakId: 'org.libretro.RetroArch',
              emudeckLauncher: 'retroarch.sh',
            );
      if (executable == null) return RaLaunchReadiness.unknown;
      final settings =
          await RetroArchVisualSession.configuredAchievementSettings(
            executable: executable,
            coreFilename: core,
            romPath: path,
            username: username,
          );
      if (settings == null) return RaLaunchReadiness.unknown;
      if (!settings.accountMatches) return RaLaunchReadiness.warning;
      return fromSettings(
        achievements: settings.achievements,
        hardcore: settings.hardcore,
      );
    } catch (_) {
      return RaLaunchReadiness.unknown;
    }
  }

  static RaLaunchReadiness fromSettings({
    required bool? achievements,
    required bool? hardcore,
  }) {
    if (achievements == false || hardcore == false) {
      return RaLaunchReadiness.warning;
    }
    if (achievements == true && hardcore == true) {
      return RaLaunchReadiness.verified;
    }
    return RaLaunchReadiness.unknown;
  }
}
