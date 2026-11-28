import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_artwork_layout.dart';
import 'package:neostation/widgets/game_media_composite.dart';

void main() {
  test('a saved Rows preference resolves to Fan', () {
    expect(GameArtworkLayout.fromPreference('rows'), GameArtworkLayout.fan);
    expect(GameArtworkLayout.fromPreference('fan'), GameArtworkLayout.fan);
    expect(GameArtworkLayout.fromPreference(null), GameArtworkLayout.dynamic);
  });

  testWidgets('shows the four media slots at Steam Deck size', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> render({
      String cover = '',
      String title = '',
      String shot = '',
      String icon = '',
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 480,
              height: 360,
              child: GameMediaComposite(
                cover: cover,
                titleScreen: title,
                screenshot: shot,
                icon: icon,
                fallback: const Text('Missing media'),
              ),
            ),
          ),
        ),
      );
    }

    await render(
      cover: 'cover.png',
      title: 'title.png',
      shot: 'shot.png',
      icon: 'icon.png',
    );
    final images = find.byType(Image);
    expect(images, findsNWidgets(4));
    for (final image in tester.widgetList<Image>(images)) {
      expect(image.fit, BoxFit.contain);
      expect(image.image, isA<ResizeImage>());
    }
    expect(
      tester.getSize(images.at(0)).width,
      greaterThan(tester.getSize(images.at(1)).width),
    );
    expect(
      tester.getTopLeft(images.at(1)).dy,
      lessThan(tester.getTopLeft(images.at(2)).dy),
    );

    await render(shot: 'shot.png');
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Missing media'), findsNothing);

    await render();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Missing media'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switches the four artwork roles without clipping or repeating files',
    (tester) async {
      for (final layout in GameArtworkLayout.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 550,
                height: 300,
                child: GameMediaComposite(
                  cover: 'cover.png',
                  titleScreen: 'title.png',
                  screenshot: 'shot.png',
                  logo: 'logo.png',
                  icon: 'logo.png',
                  layout: layout,
                  fallback: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        final images = find.byType(Image);
        expect(
          images,
          findsNWidgets(layout == GameArtworkLayout.dynamic ? 3 : 4),
        );
        expect(
          find.byKey(const ValueKey('logo.png')),
          layout == GameArtworkLayout.dynamic ? findsNothing : findsOneWidget,
        );
        final first = tester.getTopLeft(images.at(0));
        final second = tester.getTopLeft(images.at(1));
        if (layout == GameArtworkLayout.stacked) {
          expect(first.dy, lessThan(second.dy));
        } else if (layout == GameArtworkLayout.fan) {
          expect(first.dx, lessThan(second.dx));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('logo and cover fallbacks use space at external display size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> render(GameArtworkLayout layout, String cover, String logo) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 640,
                height: 480,
                child: GameMediaComposite(
                  cover: cover,
                  titleScreen: '',
                  screenshot: 'shot.png',
                  logo: logo,
                  icon: 'icon.png',
                  layout: layout,
                  fallback: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );

    for (final layout in [GameArtworkLayout.stacked, GameArtworkLayout.fan]) {
      await render(layout, 'cover.png', '');
      final cover = find.byKey(const ValueKey('cover.png'));
      final screenshot = find.byKey(const ValueKey('shot.png'));
      expect(cover, findsOneWidget);
      if (layout == GameArtworkLayout.stacked) {
        expect(
          tester.getTopLeft(cover).dy,
          lessThan(tester.getTopLeft(screenshot).dy),
        );
      } else {
        expect(
          tester.getTopLeft(cover).dx,
          lessThan(tester.getTopLeft(screenshot).dx),
        );
      }

      await render(layout, '', '');
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    }
  });
}
