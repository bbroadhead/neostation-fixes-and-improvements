import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/scraping_provider.dart';
import 'package:neostation/screens/settings_screen/new_settings_options/screenscraper/screenscraper_settings_content.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:neostation/services/screenscraper_service.dart';
import 'package:neostation/services/steam_grid_db_artwork_service.dart';
import 'package:neostation/screens/settings_screen/new_settings_options/screenscraper/steam_grid_db_key_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dbHelper = DatabaseTestHelper();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  setUp(() async {
    CredentialStore.debugUseBackends(preferEncryptedFile: false);
    await dbHelper.setUp();
  });

  tearDown(() async {
    CredentialStore.debugReset();
    await dbHelper.tearDown();
  });

  testWidgets('validates the key before showing visible success and saving', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final client = MockClient(
      (request) async => request.headers['authorization'] == 'Bearer valid-key'
          ? http.Response(
              '{"success":true,"data":[{"name":"Portal 2","id":17830}]}',
              200,
            )
          : http.Response('{"success":false}', 401),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterLocalization.instance.localizationsDelegates,
        supportedLocales: FlutterLocalization.instance.supportedLocales,
        home: SteamGridDbKeyDialog(client: client),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    final save = find.widgetWithText(TextButton, 'Save');

    await tester.enterText(field, 'invalid-key');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('The API key was rejected.'), findsOneWidget);
    expect(find.text('Connection successful'), findsNothing);
    expect(await SteamGridDbArtworkService.readSavedApiKey(), isNull);

    await tester.enterText(field, ' valid-key ');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Connection successful'), findsOneWidget);
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    expect(await SteamGridDbArtworkService.readSavedApiKey(), 'valid-key');

    await tester.enterText(field, 'invalid-key');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Connection successful'), findsNothing);
    expect(await SteamGridDbArtworkService.readSavedApiKey(), 'valid-key');
  });

  testWidgets('scraper API settings can be saved without ScreenScraper login', (
    tester,
  ) async {
    await SteamGridDbArtworkService.saveApiKey('fixture-key');
    final key = GlobalKey<ScreenScraperSettingsContentState>();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: ScreenUtilInit(
          designSize: const Size(1920, 1080),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: ChangeNotifierProvider(
                create: (_) => ScrapingProvider(),
                child: ScreenScraperSettingsContent(
                  key: key,
                  isContentFocused: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // The credential lookup hits the real test database; let it settle.
    for (var i = 0; i < 20 && key.currentState!.getItemCount() == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump();

    expect(find.text('Metadata'), findsOneWidget);
    expect(find.text('ScreenScraper Login'), findsOneWidget);
    expect(
      key.currentState!.getItemCount(),
      ScreenScraperService.usesLibretroArtwork ? 5 : 4,
    );
    if (ScreenScraperService.usesLibretroArtwork) {
      expect(find.text('Scrape all ROMs'), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('SteamGridDB API key')).dy,
      lessThan(tester.getTopLeft(find.text('ScreenScraper Login')).dy),
    );
    expect(
      tester.getTopLeft(find.text('ScreenScraper Login')).dy,
      lessThan(tester.getTopLeft(find.text('ScreenScraper developer API')).dy),
    );
    expect(key.currentState!.navigateBack(), isFalse);
    key.currentState!.selectItem();
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, 'fixture-key');
    await tester.enterText(field, '');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    key.currentState!.selectItem();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(key.currentState!.navigateDown(), isTrue);
    expect(key.currentState!.navigateDown(), isTrue);
    key.currentState!.selectItem();
    await tester.pumpAndSettle();
    final developerId = find.widgetWithText(TextField, 'devid');
    final developerPassword = find.widgetWithText(TextField, 'devpassword');
    expect(tester.widget<TextField>(developerPassword).obscureText, isTrue);
    await tester.enterText(developerId, ' fixture-dev ');
    await tester.pump();
    await tester.showKeyboard(developerPassword);
    await tester.pump();
    await tester.enterText(developerPassword, 'fixture-password');
    await tester.pump();
    expect(
      tester.widget<TextField>(developerPassword).controller!.text,
      'fixture-password',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(developerId, findsNothing);

    key.currentState!.selectItem();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(developerId).controller!.text,
      'fixture-dev',
    );
    expect(
      tester.widget<TextField>(developerPassword).controller!.text,
      'fixture-password',
    );
    await tester.enterText(developerId, '');
    await tester.pump();
    await tester.showKeyboard(developerPassword);
    await tester.pump();
    await tester.enterText(developerPassword, '');
    await tester.pump();
    final save = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(developerId, findsNothing);

    expect(key.currentState!.navigateDown(), isTrue);
    key.currentState!.selectItem();
    await tester.pumpAndSettle();
    expect(await ScreenScraperService.getScrapeWorkers(), 5);
  });
}
