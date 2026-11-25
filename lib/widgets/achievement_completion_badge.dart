import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../l10n/app_locale.dart';
import '../providers/retro_achievements_provider.dart';

/// An account award reported by RetroAchievements for a matched game.
class AchievementCompletionBadge extends StatelessWidget {
  const AchievementCompletionBadge({
    super.key,
    required this.gameId,
    this.size = 16,
  });

  final int? gameId;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (gameId == null || gameId! <= 0) return const SizedBox.shrink();
    final status = context
        .select<RetroAchievementsProvider?, (bool, String?, int?)>(
          (provider) => (
            provider?.isConnected == true,
            provider?.libraryAward(gameId),
            provider?.cacheGeneration,
          ),
        );
    if (!status.$1) return const SizedBox.shrink();
    final provider = context.read<RetroAchievementsProvider?>();
    // The provider coalesces requests across all visible library tiles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider?.refreshLibraryAwards();
    });
    final (color, title, mode) = switch (status.$2) {
      'mastered' => (
        const Color(0xffffd25c),
        AppLocale.raFilterMastered,
        AppLocale.raHardcore,
      ),
      'beaten-hardcore' => (
        const Color(0xffd4dbe5),
        AppLocale.raFilterBeaten,
        AppLocale.raHardcore,
      ),
      'beaten-softcore' => (
        const Color(0xffd4dbe5),
        AppLocale.raFilterBeaten,
        AppLocale.raCasual,
      ),
      _ => (null, null, null),
    };
    if (color == null || title == null || mode == null) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: '${title.getString(context)} · ${mode.getString(context)}',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black87,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Symbols.emoji_events_rounded, color: color, size: size),
        ),
      ),
    );
  }
}
