import 'package:neostation/services/visual_profiles/gameplay_viewport.dart';
import 'package:test/test.dart';

void main() {
  const display = (width: 1280, height: 800);

  test('scales the artwork to cover the display and clips its outer edges', () {
    expect(
      GameplayViewport.visibleOpening(
        display: display,
        artwork: (width: 1920, height: 1080),
        opening: (x: 690, y: 297, width: 540, height: 486),
      ),
      (x: 440, y: 220, width: 400, height: 360),
    );
  });

  test('rejects an opening cropped entirely outside the display', () {
    expect(
      GameplayViewport.visibleOpening(
        display: display,
        artwork: (width: 2000, height: 800),
        opening: (x: 0, y: 0, width: 300, height: 800),
      ),
      isNull,
    );
  });

  test('uses integer scaling when the opening nearly fits an integer step', () {
    expect(
      GameplayViewport.fit(
        opening: (x: 300, y: 80, width: 520, height: 460),
        aspectRatio: 10 / 9,
        nativeHeight: 144,
      ),
      (x: 320, y: 94, width: 480, height: 432),
    );
  });

  test('fits a wide PSP frame independent of internal render resolution', () {
    expect(
      GameplayViewport.fit(
        opening: (x: 0, y: 0, width: 1280, height: 800),
        aspectRatio: 16 / 9,
        nativeHeight: 272,
      ),
      (x: 0, y: 40, width: 1280, height: 720),
    );
  });

  test('constrains position and size for vertical arcade content', () {
    expect(
      GameplayViewport.fit(
        opening: (x: 500, y: 100, width: 300, height: 600),
        aspectRatio: 3 / 4,
        size: 0.5,
        horizontal: 5,
        vertical: -2,
      ),
      (x: 650, y: 100, width: 150, height: 200),
    );
  });

  test('shrinks gameplay below native resolution if needed', () {
    expect(
      GameplayViewport.fit(
        opening: (x: 100, y: 100, width: 180, height: 100),
        aspectRatio: 3 / 2,
        nativeHeight: 160,
      ),
      (x: 115, y: 100, width: 150, height: 100),
    );
  });
}
