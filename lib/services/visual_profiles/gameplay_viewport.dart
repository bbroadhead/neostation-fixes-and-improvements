import 'dart:math' as math;

typedef PixelRect = ({int x, int y, int width, int height});

/// Fits a whole frame inside a single transparent opening in a border.
///
/// The artwork covers the display while retaining its aspect ratio. Only the
/// visible intersection of its opening and the display may contain gameplay.
/// Dual-screen cores can use this with an opening for their combined frame.
class GameplayViewport {
  const GameplayViewport._();

  static PixelRect? visibleOpening({
    required ({int width, int height}) display,
    required ({int width, int height}) artwork,
    required PixelRect opening,
  }) {
    if (display.width <= 0 ||
        display.height <= 0 ||
        artwork.width <= 0 ||
        artwork.height <= 0 ||
        opening.width <= 0 ||
        opening.height <= 0 ||
        opening.x < 0 ||
        opening.y < 0 ||
        opening.x + opening.width > artwork.width ||
        opening.y + opening.height > artwork.height) {
      return null;
    }

    final scale = math.max(
      display.width / artwork.width,
      display.height / artwork.height,
    );
    final left = (display.width - artwork.width * scale) / 2;
    final top = (display.height - artwork.height * scale) / 2;
    final x = math.max(0, (left + opening.x * scale).ceil());
    final y = math.max(0, (top + opening.y * scale).ceil());
    final right = math.min(
      display.width,
      (left + (opening.x + opening.width) * scale).floor(),
    );
    final bottom = math.min(
      display.height,
      (top + (opening.y + opening.height) * scale).floor(),
    );
    if (right <= x || bottom <= y) return null;
    return (x: x, y: y, width: right - x, height: bottom - y);
  }

  /// [horizontal] and [vertical] range from -1 to 1, with zero centering
  /// gameplay. [size] is the fraction of the largest fitting viewport.
  ///
  /// Integer scaling uses the native frame height as its unit, with width
  /// derived from the display aspect ratio to accommodate non-square pixels.
  static PixelRect? fit({
    required PixelRect opening,
    required double aspectRatio,
    int? nativeHeight,
    bool preferInteger = true,
    double size = 1,
    double horizontal = 0,
    double vertical = 0,
  }) {
    if (opening.width <= 0 ||
        opening.height <= 0 ||
        !aspectRatio.isFinite ||
        aspectRatio <= 0 ||
        !size.isFinite ||
        !horizontal.isFinite ||
        !vertical.isFinite ||
        (nativeHeight != null && nativeHeight <= 0)) {
      return null;
    }

    final heightLimit = math.min(
      opening.height.toDouble(),
      opening.width / aspectRatio,
    );
    final targetHeight = heightLimit * size.clamp(0.0, 1.0);
    final integerHeight = nativeHeight == null
        ? 0
        : (targetHeight / nativeHeight).floor() * nativeHeight;
    // Keep the fitting area when an integer step would leave too much unused.
    final height =
        preferInteger &&
            integerHeight > 0 &&
            integerHeight >= targetHeight * 0.85
        ? integerHeight
        : targetHeight.floor();
    final width = (height * aspectRatio).round();
    if (width <= 0 || height <= 0 || width > opening.width) return null;

    final x = ((opening.width - width) * (1 + horizontal.clamp(-1, 1)) / 2)
        .round();
    final y = ((opening.height - height) * (1 + vertical.clamp(-1, 1)) / 2)
        .round();
    return (x: opening.x + x, y: opening.y + y, width: width, height: height);
  }
}
