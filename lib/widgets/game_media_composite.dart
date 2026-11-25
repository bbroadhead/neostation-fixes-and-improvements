import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_artwork_layout.dart';

class GameMediaComposite extends StatelessWidget {
  const GameMediaComposite({
    super.key,
    required this.cover,
    required this.titleScreen,
    required this.screenshot,
    this.logo = '',
    this.icon = '',
    this.layout = GameArtworkLayout.dynamic,
    required this.fallback,
  });

  final String cover;
  final String titleScreen;
  final String screenshot;
  final String logo;
  final String icon;
  final GameArtworkLayout layout;
  final Widget fallback;

  Widget _image(String path) => Image.file(
    File(path),
    fit: BoxFit.contain,
    cacheWidth: 640,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );

  Widget _group(List<String> paths, Axis axis) => Flex(
    direction: axis,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [for (final path in paths) Expanded(child: _image(path))],
  );

  @override
  Widget build(BuildContext context) {
    final paths = {cover, titleScreen, screenshot, logo}..remove('');
    final primary = paths.contains(cover) ? cover : paths.firstOrNull;
    final secondary = paths.where((path) => path != primary).toList();
    if (primary == null) return icon.isEmpty ? fallback : _image(icon);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showIcon = icon.isNotEmpty && !paths.contains(icon);
        final iconSize = (constraints.maxWidth * .12).clamp(12.0, 42.0);
        final gap = math.min(10.0, constraints.maxWidth * .025);
        final panels = <String>[primary, ...secondary];
        final grouped = switch (layout) {
          GameArtworkLayout.dynamic => _dynamic(context, primary, secondary),
          GameArtworkLayout.stacked || GameArtworkLayout.rows => Flex(
            spacing: 8,
            direction: layout == GameArtworkLayout.stacked
                ? Axis.horizontal
                : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < panels.length; index += 2)
                Expanded(
                  child: _group(
                    panels.skip(index).take(2).toList(),
                    layout == GameArtworkLayout.stacked
                        ? Axis.vertical
                        : Axis.horizontal,
                  ),
                ),
            ],
          ),
        };
        return Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            children: [
              Expanded(child: grouped),
              if (showIcon)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: iconSize,
                    child: _image(icon),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _dynamic(BuildContext context, String primary, List<String> others) {
    if (others.isEmpty) return _image(primary);
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlap = math.min(12.0, constraints.maxWidth * .035);
        return Stack(
          children: [
            Positioned.fill(
              right: constraints.maxWidth * .42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.only(right: overlap + 3),
                  child: _image(primary),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 4,
              bottom: 4,
              width: constraints.maxWidth * .42 + overlap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: .25),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _group(others, Axis.vertical),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
