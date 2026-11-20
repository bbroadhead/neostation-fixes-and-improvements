import 'dart:io';

import 'package:flutter/material.dart';

class GameMediaComposite extends StatelessWidget {
  const GameMediaComposite({
    super.key,
    required this.cover,
    required this.titleScreen,
    required this.screenshot,
    required this.icon,
    required this.fallback,
  });

  final String cover;
  final String titleScreen;
  final String screenshot;
  final String icon;
  final Widget fallback;

  Widget _image(String path, int cacheWidth) => Image.file(
    File(path),
    fit: BoxFit.contain,
    cacheWidth: cacheWidth,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context) {
    final secondary = [
      titleScreen,
      screenshot,
    ].where((path) => path.isNotEmpty);
    if (cover.isEmpty && secondary.isEmpty && icon.isEmpty) return fallback;

    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = (constraints.maxWidth * 0.14).clamp(16.0, 48.0);
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cover.isNotEmpty)
                      Expanded(flex: 3, child: _image(cover, 480)),
                    if (cover.isNotEmpty && secondary.isNotEmpty)
                      const SizedBox(width: 8),
                    if (secondary.isNotEmpty)
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final path in secondary)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: _image(path, 320),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (cover.isEmpty && secondary.isEmpty)
                      Expanded(child: _image(icon, 96)),
                  ],
                ),
              ),
              if (icon.isNotEmpty && (cover.isNotEmpty || secondary.isNotEmpty))
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: iconSize,
                    child: _image(icon, 96),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
