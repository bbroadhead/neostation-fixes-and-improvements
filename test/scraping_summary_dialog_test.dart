import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/artwork_scrape_event.dart';
import 'package:neostation/widgets/scraping_summary_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  testWidgets('summary lists issue types and returns the retry action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? retry;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(640, 480),
        builder: (_, _) => MaterialApp(
          localizationsDelegates:
              FlutterLocalization.instance.localizationsDelegates,
          supportedLocales: FlutterLocalization.instance.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                retry = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ScrapingSummaryDialog(
                    totalGames: 2,
                    successfulGames: 1,
                    failedGames: 1,
                    elapsedTime: '3s',
                    imagesDownloaded: 3,
                    imagesAssigned: 2,
                    imagesSkippedManual: 1,
                    issues: [
                      (
                        romPath: '/games/a.nes',
                        name: 'Game A',
                        categories: {
                          'box2d': ArtworkScrapeEvent.unavailable,
                          'icons': ArtworkScrapeEvent.failed,
                        },
                        gameFailed: true,
                      ),
                    ],
                    canRetry: true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Images assigned'), findsOneWidget);
    expect(find.text('Game A'), findsOneWidget);
    expect(find.textContaining('Boxart · Unavailable'), findsOneWidget);
    expect(find.textContaining('Game Icon · Failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('Retry'));
    await tester.pumpAndSettle();
    expect(retry, isTrue);
  });
}
