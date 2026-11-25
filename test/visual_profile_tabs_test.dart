import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/visual_profile.dart';
import 'package:neostation/screens/settings_screen/new_settings_options/visual_border_dialog.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SfxService().setEnabled(false);
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  testWidgets('shader edits preserve the stored bezel while switching tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final localization = FlutterLocalization.instance;
    VisualBorderResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: localization.localizationsDelegates,
        supportedLocales: localization.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<VisualBorderResult>(
                  context: context,
                  builder: (_) => const VisualBorderDialog(
                    system: 'ds-no-layout-test',
                    profile: VisualProfile(borderId: 'saved-border'),
                    previewGeometry: null,
                    shaderFormat: 'glsl',
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
    expect(find.text('Gameplay size'), findsOneWidget);
    await tester.tap(find.text('Shader'));
    await tester.pumpAndSettle();
    expect(find.text('Gameplay size'), findsNothing);
    await tester.tap(find.text('Preset default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(find.text('Sharp Bilinear Simple'), findsOneWidget);
    expect(find.text('Static RetroArch preview · GLSL'), findsOneWidget);

    await tester.tap(find.text('Console border'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shader'));
    await tester.pumpAndSettle();
    expect(find.text('Sharp Bilinear Simple'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.profile?.borderId, 'saved-border');
    expect(saved?.profile?.shaderId, '@sharp');
  });
}
