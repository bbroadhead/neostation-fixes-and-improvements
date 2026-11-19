import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../l10n/app_locale.dart';
import '../../../../services/gamepad/gamepad_navigation_manager.dart';
import '../../../../services/libretro_thumbnail_service.dart';
import '../../../../utils/gamepad_nav.dart';

class LibretroArtworkDialog extends StatefulWidget {
  const LibretroArtworkDialog({
    super.key,
    required this.load,
    required this.isCurrent,
  });

  final Future<List<LibretroArtwork>> Function(bool Function()) load;
  final Future<bool> Function(LibretroArtwork) isCurrent;

  @override
  State<LibretroArtworkDialog> createState() => _LibretroArtworkDialogState();
}

class _LibretroArtworkDialogState extends State<LibretroArtworkDialog> {
  static const _columns = 3;
  late final String _layerId = 'libretro_artwork#${identityHashCode(this)}';
  late final GamepadNavigation _navigation;
  List<LibretroArtwork>? _images;
  final _current = <LibretroArtwork>{};
  int _selected = 0;
  int _categoryIndex = 0;

  List<String> get _categories => [
    '',
    ...?_images?.map((image) => image.category).toSet(),
  ];

  List<LibretroArtwork>? get _visible {
    if (_categoryIndex == 0) return _images;
    final category = _categories[_categoryIndex];
    return _images?.where((image) => image.category == category).toList();
  }

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateLeft: () => _move(-1),
      onNavigateRight: () => _move(1),
      onNavigateUp: () => _move(-_columns),
      onNavigateDown: () => _move(_columns),
      onSelectItem: _apply,
      onBack: () => Navigator.of(context).pop(),
      onLeftBumper: () =>
          _selectCategory((_categoryIndex - 1) % _categories.length),
      onRightBumper: () =>
          _selectCategory((_categoryIndex + 1) % _categories.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigation.initialize();
      GamepadNavigationManager.pushLayer(
        _layerId,
        onActivate: _navigation.activate,
        onDeactivate: _navigation.deactivate,
      );
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await widget.load(() => !mounted);
      final valid = <LibretroArtwork>[];
      for (final image in results) {
        if (!mounted) return;
        try {
          final decoded = await decodeImageFromList(image.bytes);
          decoded.dispose();
          valid.add(image);
          if (await widget.isCurrent(image)) _current.add(image);
        } catch (_) {
          // A provider response with a PNG header can still be truncated.
        }
      }
      if (mounted) {
        setState(() {
          _images = valid;
          if (_current.isNotEmpty) _selected = valid.indexOf(_current.first);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _images = []);
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layerId);
    _navigation.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final images = _visible;
    if (images == null || images.isEmpty) return;
    setState(() => _selected = (_selected + delta).clamp(0, images.length - 1));
  }

  void _apply() {
    final images = _visible;
    if (images == null || images.isEmpty) return;
    Navigator.of(context).pop(images[_selected]);
  }

  void _selectCategory(int index) => setState(() {
    _categoryIndex = index;
    _selected = 0;
  });

  String _category(String category) => switch (category) {
    '' => AppLocale.allContent.getString(context),
    'box2d' => AppLocale.boxart.getString(context),
    'screenshots' => AppLocale.screenshot.getString(context),
    _ => AppLocale.libretroTitleScreen.getString(context),
  };

  @override
  Widget build(BuildContext context) {
    final images = _visible;
    return AlertDialog(
      title: Text('${AppLocale.scrapingMedia.getString(context)} · Libretro'),
      content: SizedBox(
        width: 420.r,
        height: 235.r,
        child: images == null
            ? const Center(child: CircularProgressIndicator())
            : images.isEmpty
            ? Center(
                child: Text(
                  AppLocale.scrapeMediaDownloadsFailed.getString(context),
                ),
              )
            : Column(
                children: [
                  Wrap(
                    spacing: 6.r,
                    children: [
                      for (final (index, category) in _categories.indexed)
                        ChoiceChip(
                          label: Text(_category(category)),
                          selected: index == _categoryIndex,
                          onSelected: (_) => _selectCategory(index),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: GridView.count(
                            crossAxisCount: _columns,
                            children: [
                              for (final (index, candidate) in images.indexed)
                                InkWell(
                                  onTap: () =>
                                      setState(() => _selected = index),
                                  child: Card(
                                    color: index == _selected
                                        ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                        : null,
                                    child: Padding(
                                      padding: EdgeInsets.all(4.r),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Image.memory(
                                              candidate.bytes,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                          Text(
                                            _category(candidate.category),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (_current.contains(candidate))
                                            Icon(
                                              Icons.check_circle_outline,
                                              size: 11.r,
                                              semanticLabel: AppLocale.selected
                                                  .getString(context),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.r),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: Image.memory(
                                  images[_selected].bytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Text(_category(images[_selected].category)),
                              Text(
                                images[_selected].title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocale.cancel.getString(context)),
        ),
        FilledButton(
          onPressed: images?.isNotEmpty == true ? _apply : null,
          child: Text(AppLocale.apply.getString(context)),
        ),
      ],
    );
  }
}
