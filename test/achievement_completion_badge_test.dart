import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/widgets/achievement_completion_badge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Awards extends RetroAchievementsProvider {
  String? kind;
  @override
  bool get isConnected => true;
  @override
  String? libraryAward(int? gameId) => gameId == 228 ? kind : null;
  @override
  Future<void> refreshLibraryAwards() async {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  testWidgets(
    'shows one official award and hides missing or unrecognized awards',
    (tester) async {
      final provider = _Awards();
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<RetroAchievementsProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: const Scaffold(body: AchievementCompletionBadge(gameId: 228)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final icon = find.byIcon(Symbols.emoji_events_rounded);
      expect(icon, findsNothing);
      for (final (kind, color) in [
        ('beaten-softcore', const Color(0xffd4dbe5)),
        ('beaten-hardcore', const Color(0xffd4dbe5)),
        ('mastered', const Color(0xffffd25c)),
      ]) {
        provider.kind = kind;
        provider.notifyListeners();
        await tester.pump();
        expect(icon, findsOneWidget);
        expect(tester.widget<Icon>(icon).color, color);
      }
      provider.kind = 'completed';
      provider.notifyListeners();
      await tester.pump();
      expect(icon, findsNothing);
    },
  );
}
