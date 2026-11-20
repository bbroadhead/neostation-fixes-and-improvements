import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/widgets/game_media_composite.dart';

void main() {
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
}
