import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/screens/game_screen/game_options_dialog.dart';
import 'package:neostation/screens/game_screen/game_settings_dialog/game_settings_dialog.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';
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

  const system = SystemModel(
    id: 'nes',
    folderName: 'nes',
    realName: 'NES',
    iconImage: '',
    color: '#000000',
  );
  const game = GameModel(
    romname: 'Game.nes',
    realname: 'Game',
    name: 'Game',
    year: '',
    developer: '',
    publisher: '',
    genre: '',
    players: '',
    rating: 0,
    systemFolderName: 'nes',
    playTime: 60,
  );

  for (final origin in ['List View', 'Grid View', 'Collection', 'Search']) {
    for (final save in [false, true]) {
      testWidgets(
        '$origin remains mounted after ${save ? 'confirm' : 'cancel'}',
        (tester) async {
          final database = DatabaseTestHelper();
          final db = await database.setUp();
          await db.execute(SqliteMigrations.createAppRommRomMapTableSql);
          await db.execute(
            "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('nes', 'NES', 'nes')",
          );
          await db.execute(
            "INSERT INTO user_roms (filename, rom_path, app_system_id, play_time) "
            "VALUES ('Game.nes', '/fixture/Game.nes', 'nes', 60)",
          );
          final files = FileProvider();
          addTearDown(files.dispose);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 800);
          addTearDown(tester.view.reset);

          final navigator = GlobalKey<NavigatorState>();
          var saves = 0;
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => SqliteConfigProvider()),
                ChangeNotifierProvider(create: (_) => RommProvider()),
              ],
              child: ScreenUtilInit(
                designSize: const Size(1920, 1080),
                builder: (_, _) => MaterialApp(
                  navigatorKey: navigator,
                  localizationsDelegates:
                      FlutterLocalization.instance.localizationsDelegates,
                  supportedLocales:
                      FlutterLocalization.instance.supportedLocales,
                  home: const Scaffold(body: Text('Home fixture')),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scroll = ScrollController(initialScrollOffset: 70);
          addTearDown(scroll.dispose);
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    Text(origin),
                    Expanded(
                      child: ListView(
                        controller: scroll,
                        children: [
                          for (var i = 0; i < 30; i++)
                            SizedBox(height: 32, child: Text('Game $i')),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final action = await showGameOptionsDialog(
                          context: context,
                          gameTitle: game.name,
                          targets: const [],
                          canScrape: false,
                          canIdentify: false,
                          createTargetLabel: null,
                        );
                        if (!context.mounted ||
                            action != GameOptionsAction.settings) {
                          return;
                        }
                        await showDialog<void>(
                          context: context,
                          builder: (_) => GameSettingsDialog(
                            game: game,
                            system: system,
                            isAllMode: origin == 'Collection',
                            fileProvider: files,
                            onGameUpdated: () => saves++,
                          ),
                        );
                      },
                      child: const Text('Open game options'),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final libraryNavigation = GamepadNavigation(
            onBack: () => navigator.currentState!.pop(),
          );
          const libraryLayer = 'game_settings_navigation_test_library';
          libraryNavigation.initialize();
          GamepadNavigationManager.pushLayer(
            libraryLayer,
            onActivate: libraryNavigation.activate,
            onDeactivate: libraryNavigation.deactivate,
          );
          addTearDown(() {
            GamepadNavigationManager.popLayer(libraryLayer);
            libraryNavigation.dispose();
          });
          final offset = scroll.offset;
          await tester.tap(find.text('Open game options'));
          await tester.pumpAndSettle();
          final options = tester.element(find.byType(GameOptionsDialog));
          final label = AppLocale.gameSettings.getString(options);
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          final dialog = tester.element(find.byType(GameSettingsDialog));
          await tester.tap(
            find.text(AppLocale.manage.getString(dialog).toUpperCase()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(AppLocale.playTime.getString(dialog)));
          await tester.pumpAndSettle();
          final confirmation = find.byType(ConfirmActionDialog);
          final confirmationContext = tester.element(confirmation);
          if (save) {
            await tester.tap(
              find.descendant(
                of: confirmation,
                matching: find.text(
                  AppLocale.reset.getString(confirmationContext),
                ),
              ),
            );
          } else {
            expect(GamepadNavigation.triggerBack(), isTrue);
          }
          // The confirmation remains mounted while it animates out.
          GamepadNavigation.triggerBack();
          await tester.pumpAndSettle();
          expect(find.byType(GameSettingsDialog), findsOneWidget);
          expect(confirmation, findsNothing);
          expect(saves, save ? 1 : 0);

          expect(GamepadNavigation.triggerBack(), isTrue);
          GamepadNavigation.triggerBack();
          await tester.pumpAndSettle();
          expect(find.byType(GameSettingsDialog), findsNothing);
          expect(find.text(origin), findsOneWidget);
          expect(find.text('Home fixture'), findsNothing);
          expect(scroll.offset, offset);
          expect(libraryNavigation.isActive, isTrue);
          expect(saves, save ? 1 : 0);
          final rows = await db.rawQuery(
            "SELECT play_time FROM user_roms WHERE filename = 'Game.nes'",
          );
          expect(rows.single['play_time'], save ? 0 : 60);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
