import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/screens/game_screen/game_details_card/dialogs/libretro_artwork_dialog.dart';
import 'package:neostation/services/libretro_thumbnail_service.dart';
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

  for (final apply in [false, true]) {
    testWidgets(
      'filtering and ${apply ? 'applying' : 'cancelling'} the preview',
      (tester) async {
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
        );
        final cover = (category: 'box2d', title: 'Cover', bytes: bytes);
        final shot = (category: 'screenshots', title: 'Gameplay', bytes: bytes);
        late Completer<void> decoded;
        LibretroArtwork? selected;
        var closed = false;
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
                    selected = await showDialog<LibretroArtwork>(
                      context: context,
                      builder: (_) => LibretroArtworkDialog(
                        load: (_) async => [cover, shot],
                        isCurrent: (image) async {
                          if (image == shot) decoded.complete();
                          return image == cover;
                        },
                      ),
                    );
                    closed = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          decoded = Completer<void>();
          await tester.tap(find.text('Open'));
          await tester.pump();
          await decoded.future.timeout(const Duration(seconds: 5));
        });
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        final filter = find.widgetWithText(ChoiceChip, 'Screenshot');
        await tester.tap(filter);
        await tester.pumpAndSettle();
        expect(find.text('Gameplay'), findsOneWidget);
        expect(find.text('Cover'), findsNothing);
        await tester.tap(find.text(apply ? 'Apply' : 'Cancel'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        expect(closed, isTrue);
        expect(selected, apply ? shot : isNull);
      },
    );
  }
}
