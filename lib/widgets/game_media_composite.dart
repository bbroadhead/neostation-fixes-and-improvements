import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_artwork_layout.dart';
import 'neo_glass.dart';

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
    key: ValueKey(path),
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
    final dynamicLayout = layout == GameArtworkLayout.dynamic;
    final paths = {cover, titleScreen, screenshot, icon}..remove('');
    if (dynamicLayout && logo.isNotEmpty) paths.remove(logo);
    final primary = [
      if (!dynamicLayout) logo,
      ...paths,
    ].where((path) => path.isNotEmpty).firstOrNull;
    if (primary == null) return fallback;
    paths.remove(primary);

    if (!dynamicLayout) {
      if (paths.isEmpty) return _image(primary);
      final stacked = layout == GameArtworkLayout.stacked;
      return Flex(
        direction: stacked ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Expanded(flex: stacked ? 2 : 1, child: _image(primary)),
          Expanded(
            flex: stacked ? 3 : 2,
            child: _group(
              paths.toList(),
              stacked ? Axis.horizontal : Axis.vertical,
            ),
          ),
        ],
      );
    }

    final showIcon = paths.remove(icon);
    return NeoGlass(
      cornerRadius: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = math.min(10.0, constraints.maxWidth * .025);
          final iconSize = (constraints.maxWidth * .12).clamp(12.0, 42.0);
          return Padding(
            padding: EdgeInsets.all(gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: paths.isEmpty
                      ? _image(primary)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: gap,
                          children: [
                            Expanded(flex: 58, child: _image(primary)),
                            Expanded(
                              flex: 42,
                              child: _group(paths.toList(), Axis.vertical),
                            ),
                          ],
                        ),
                ),
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
      ),
    );
  }
}
