import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/ra_compatibility.dart';
import 'package:neostation/screens/collections_screen/ra_incompatible_games_screen.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gamepad_test_clock.dart';
import 'support/plugin_channel_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    installDefaultPluginMocks();
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
    SfxService().setEnabled(false);
  });
  setUp(resetGamepadClock);
  tearDown(restoreGamepadClock);

  test('English revisions use only regions and language tags in the official filename', () {
    expect(englishRevisionOrder('Game (USA) (Rev 2).nes'), 0);
    expect(englishRevisionOrder('Game (Europe) (En,Fr).nes'), 1);
    expect(englishRevisionOrder('Game (World) (En).nes'), 2);
    expect(
      englishRevisionOrder('Game (Japan) [T+Eng] [English Translation].nes'),
      3,
    );
    expect(englishRevisionOrder('Game (Europe) (Fr,De).nes'), isNull);
    expect(englishRevisionOrder('USA Football (Japan).nes'), isNull);
  });

  testWidgets('reason filters preserve the ROM selected for Game Info', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const first = GameModel(
      romname: 'First.nes',
      realname: 'First',
      name: 'First',
      year: '',
      developer: '',
      publisher: '',
      genre: '',
      players: '',
      rating: 0,
      romPath: '/roms/First.nes',
    );
    final second = first.copyWith(
      name: 'Second',
      romname: 'Second.nes',
      romPath: '/roms/Second.nes',
    );
    final opened = <String?>[];
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(640, 480),
        builder: (_, _) => MaterialApp(
          localizationsDelegates:
              FlutterLocalization.instance.localizationsDelegates,
          supportedLocales: FlutterLocalization.instance.supportedLocales,
          home: RaIncompatibleGamesScreen(
            title: 'RetroAchievements Incompatible',
            loadGames: ({isCancelled}) async => [
              (game: first, reason: RaCompatibilityStatus.differentRomRequired),
              (game: second, reason: RaCompatibilityStatus.noAchievementSet),
            ],
            openDetails: (game) async => opened.add(game.romPath),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    final noSetLabel = AppLocale.en[AppLocale.raCompatibilityNoSet] as String;
    await tester.tap(find.widgetWithText(ChoiceChip, noSetLabel));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.widgetWithText(ListTile, noSetLabel), findsOneWidget);
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(opened, ['/roms/Second.nes']);

    advanceGamepadClock(const Duration(milliseconds: 350));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(find.text('First'), findsOneWidget);
    advanceGamepadClock(const Duration(milliseconds: 350));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['/roms/Second.nes', '/roms/First.nes']);
    expect(tester.takeException(), isNull);
  });
}
