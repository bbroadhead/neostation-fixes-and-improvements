import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../l10n/app_locale.dart';
import '../../../../services/gamepad/gamepad_navigation_manager.dart';
import '../../../../models/artwork_preview.dart';
import '../../../../utils/gamepad_nav.dart';
import '../../../../widgets/neo_glass.dart';
import '../../../../widgets/custom_notification.dart';

class ArtworkGalleryDialog extends StatefulWidget {
  const ArtworkGalleryDialog({
    super.key,
    required this.load,
    this.search,
    required this.detectedTitle,
    this.savedTitle,
    required this.isCurrent,
    this.selectedPaths,
    this.removeSelected,
  });

  final String detectedTitle;
  final String? savedTitle;
  final Future<List<ArtworkPreview>> Function(String, bool Function()) load;
  final Future<List<ArtworkPreview>> Function(String, bool Function())? search;
  final Future<bool> Function(ArtworkPreview) isCurrent;
  final Map<String, String> Function()? selectedPaths;
  final Future<void> Function(String)? removeSelected;

  @override
  State<ArtworkGalleryDialog> createState() => _ArtworkGalleryDialogState();
}

class _ArtworkGalleryDialogState extends State<ArtworkGalleryDialog> {
  static const _columns = 3;
  late final String _layerId = 'artwork_gallery#${identityHashCode(this)}';
  late final GamepadNavigation _navigation;
  List<ArtworkPreview>? _images;
  final _current = <ArtworkPreview>{};
  final _items = <GlobalKey>[];
  late final _search = TextEditingController(
    text: widget.savedTitle ?? widget.detectedTitle,
  );
  final _searchFocus = FocusNode();
  final _pending = <String, ArtworkPreview>{};
  int _request = 0;
  bool _failed = false;
  int _selected = 0;
  int? _selectedAssignment;
  bool _removing = false;
  final _assignmentScroll = ScrollController();

  Map<String, String> get _assignments => widget.selectedPaths?.call() ?? {};
  int _categoryIndex = 0;
  ArtworkProvider? _provider;

  List<ArtworkPreview>? get _source => _provider == null
      ? _images
      : _images?.where((image) => image.provider == _provider).toList();

  List<ArtworkProvider?> get _providers => [
    null,
    ...?_images?.map((image) => image.provider).toSet(),
  ];

  List<String> get _categories => [
    '',
    ...{...?_source?.map((image) => image.category), 'wheels'},
  ];

  List<ArtworkPreview>? get _visible {
    if (_categoryIndex == 0) return _source;
    final category = _categories[_categoryIndex];
    return _source?.where((image) => image.category == category).toList();
  }

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateLeft: () => _moveHorizontal(-1),
      onNavigateRight: () => _moveHorizontal(1),
      onNavigateUp: () {
        if (_selectedAssignment != null || _searchFocus.hasFocus) return;
        if (_selected < _columns && _assignments.isNotEmpty) {
          setState(() => _selectedAssignment = 0);
          _revealAssignment();
        } else {
          _move(-_columns);
        }
      },
      onNavigateDown: () {
        if (_selectedAssignment != null) {
          setState(() => _selectedAssignment = null);
        } else {
          _move(_columns);
        }
      },
      onSelectItem: () {
        if (_searchFocus.hasFocus) {
          _submit();
        } else if (_selectedAssignment case final index?) {
          final category = _assignments.keys.elementAtOrNull(index);
          if (category != null) _removeAssignment(category);
        } else {
          _choose();
        }
      },
      onBack: () {
        if (_searchFocus.hasFocus) {
          _searchFocus.unfocus();
        } else {
          Navigator.of(context).pop();
        }
      },
      onSettings: _apply,
      onFavorite: _searchFocus.requestFocus,
      onLeftBumper: () =>
          _selectCategory((_categoryIndex - 1) % _categories.length),
      onRightBumper: () =>
          _selectCategory((_categoryIndex + 1) % _categories.length),
      onXButton: () => _selectProvider(
        _providers[(_providers.indexOf(_provider) + 1) % _providers.length],
      ),
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
    _load(_search.text);
  }

  void _submit() {
    _searchFocus.unfocus();
    _load(_search.text.trim(), byName: true);
  }

  Future<void> _load(String query, {bool byName = false}) async {
    final request = ++_request;
    bool cancelled() => !mounted || request != _request;
    setState(() {
      _images = null;
      _failed = false;
      _current.clear();
      _items.clear();
      _selected = 0;
      _categoryIndex = 0;
      _provider = null;
    });
    try {
      final loader = byName && query.isNotEmpty
          ? widget.search ?? widget.load
          : widget.load;
      final results = await loader(
        query.isEmpty ? widget.detectedTitle : query,
        cancelled,
      );
      final valid = <ArtworkPreview>[];
      final current = <ArtworkPreview>{};
      for (final image in results) {
        if (cancelled()) return;
        try {
          final decoded = await decodeImageFromList(image.bytes);
          decoded.dispose();
          valid.add(image);
          if (await widget.isCurrent(image)) current.add(image);
        } catch (_) {
          // A provider response with a PNG header can still be truncated.
        }
      }
      if (cancelled()) return;
      setState(() {
        _images = valid;
        _current.addAll(current);
        _items.addAll(List.generate(valid.length, (_) => GlobalKey()));
        if (_current.isNotEmpty) _selected = valid.indexOf(_current.first);
      });
    } catch (_) {
      if (cancelled()) return;
      setState(() {
        _failed = true;
        _images = [];
      });
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layerId);
    _navigation.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _assignmentScroll.dispose();
    super.dispose();
  }

  void _moveHorizontal(int delta) {
    final index = _selectedAssignment;
    if (index == null) {
      _move(delta);
    } else if (_assignments.isNotEmpty) {
      setState(() {
        _selectedAssignment = (index + delta).clamp(0, _assignments.length - 1);
      });
      _revealAssignment();
    }
  }

  void _revealAssignment() {
    if (!_assignmentScroll.hasClients) return;
    _assignmentScroll.jumpTo(
      ((_selectedAssignment ?? 0) * 156.r).clamp(
        0.0,
        _assignmentScroll.position.maxScrollExtent,
      ),
    );
  }

  Future<void> _removeAssignment(String category) async {
    final remove = widget.removeSelected;
    if (_removing || remove == null) return;
    setState(() => _removing = true);
    try {
      await remove(category);
      if (!mounted) return;
      setState(() {
        _pending.remove(category);
        _current.removeWhere((image) => image.category == category);
        if (_assignments.isEmpty) {
          _selectedAssignment = null;
        } else if (_selectedAssignment case final index?) {
          _selectedAssignment = index.clamp(0, _assignments.length - 1);
        }
      });
    } catch (_) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.failedToSaveSetting.getString(context),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Widget _assignmentStrip(Map<String, String> assignments) => SizedBox(
    height: 42.r,
    child: ListView(
      controller: _assignmentScroll,
      scrollDirection: Axis.horizontal,
      children: [
        for (final (index, entry) in assignments.entries.indexed)
          SizedBox(
            width: 156.r,
            child: OutlinedButton(
              onPressed: _removing ? null : () => _removeAssignment(entry.key),
              style: _selectedAssignment == index
                  ? OutlinedButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                    )
                  : null,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 26.r,
                    child: Image.file(
                      File(entry.value),
                      fit: BoxFit.contain,
                      cacheWidth: 64,
                    ),
                  ),
                  SizedBox(width: 4.r),
                  Expanded(
                    child: Text(
                      '${_category(entry.key)} · ${AppLocale.removeImage.getString(context)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  void _move(int delta) {
    final images = _visible;
    if (images == null || images.isEmpty) return;
    setState(() => _selected = (_selected + delta).clamp(0, images.length - 1));
    _revealSelection();
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _items.elementAtOrNull(_selected)?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.5);
    });
  }

  void _choose() {
    final image = _visible?.elementAtOrNull(_selected);
    if (image == null) return;
    setState(() => _pending[image.category] = image);
  }

  void _apply() {
    if (_pending.isEmpty) return;
    Navigator.of(context).pop(_pending.values.toList());
  }

  void _selectCategory(int index) {
    setState(() {
      _categoryIndex = index;
      _selected = 0;
    });
    _revealSelection();
  }

  void _selectProvider(ArtworkProvider? provider) {
    setState(() {
      _provider = provider;
      _categoryIndex = 0;
      _selected = 0;
    });
    _revealSelection();
  }

  String _providerName(ArtworkProvider? provider) =>
      provider?.displayName ?? AppLocale.allContent.getString(context);

  String _category(String category) => switch (category) {
    '' => AppLocale.allContent.getString(context),
    'box2d' => AppLocale.boxart.getString(context),
    'screenshots' => AppLocale.screenshot.getString(context),
    'icons' => AppLocale.galleryGameIcon.getString(context),
    'wheels' => AppLocale.artworkLogo.getString(context),
    'fanarts' => AppLocale.fanart.getString(context),
    _ => AppLocale.libretroTitleScreen.getString(context),
  };

  @override
  Widget build(BuildContext context) {
    final images = _visible;
    final assignments = _assignments;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: NeoGlass(
        cornerRadius: 28,
        child: AlertDialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(AppLocale.scrapingMedia.getString(context)),
          content: SizedBox(
            width: 560.r,
            height: 290.r,
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: AppLocale.scrapeSearchTitle.getString(context),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: AppLocale.resetToDefault.getString(context),
                          onPressed: () {
                            _search.text = widget.detectedTitle;
                            _searchFocus.unfocus();
                            _load(widget.detectedTitle);
                          },
                          icon: const Icon(Icons.restore),
                        ),
                        IconButton(
                          tooltip: AppLocale.scrapeSearchTitle.getString(
                            context,
                          ),
                          onPressed: _submit,
                          icon: const Icon(Icons.search),
                        ),
                      ],
                    ),
                  ),
                ),
                if (assignments.isNotEmpty) _assignmentStrip(assignments),
                Expanded(
                  child: images == null
                      ? const Center(child: CircularProgressIndicator())
                      : _images!.isEmpty
                      ? Center(
                          child: Text(
                            (_failed
                                    ? AppLocale.scrapeMediaDownloadsFailed
                                    : AppLocale.noGamesFoundFor)
                                .getString(context)
                                .replaceFirst('{name}', _search.text),
                          ),
                        )
                      : Column(
                          children: [
                            if (_providers.length > 1)
                              Wrap(
                                spacing: 6.r,
                                children: [
                                  for (final provider in _providers)
                                    ChoiceChip(
                                      label: Text(
                                        provider == null
                                            ? AppLocale.galleryAllProviders
                                                  .getString(context)
                                            : _providerName(provider),
                                      ),
                                      selected: provider == _provider,
                                      onSelected: (_) =>
                                          _selectProvider(provider),
                                    ),
                                ],
                              ),
                            Wrap(
                              spacing: 6.r,
                              children: [
                                for (final (index, category)
                                    in _categories.indexed)
                                  ChoiceChip(
                                    label: Text(_category(category)),
                                    selected: index == _categoryIndex,
                                    onSelected: (_) => _selectCategory(index),
                                  ),
                              ],
                            ),
                            if (images.isEmpty)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    AppLocale.searchNoResults.getString(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            if (images.isNotEmpty)
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: GridView.count(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          crossAxisCount: _columns,
                                          children: [
                                            for (final (index, candidate)
                                                in images.indexed)
                                              InkWell(
                                                key: _items[index],
                                                onTap: () => setState(
                                                  () => _selected = index,
                                                ),
                                                child: Card(
                                                  color: index == _selected
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer
                                                      : null,
                                                  child: Padding(
                                                    padding: EdgeInsets.all(
                                                      4.r,
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        Expanded(
                                                          child: Image.memory(
                                                            candidate.bytes,
                                                            fit: BoxFit.contain,
                                                            cacheWidth: 160,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${_providerName(candidate.provider)} · ${_category(candidate.category)}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        if (_pending[candidate
                                                                    .category] ==
                                                                candidate ||
                                                            (!_pending.containsKey(
                                                                  candidate
                                                                      .category,
                                                                ) &&
                                                                _current
                                                                    .contains(
                                                                      candidate,
                                                                    )))
                                                          Icon(
                                                            Icons
                                                                .check_circle_outline,
                                                            size: 11.r,
                                                            semanticLabel:
                                                                AppLocale
                                                                    .selected
                                                                    .getString(
                                                                      context,
                                                                    ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
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
                                          Text(
                                            '${_providerName(images[_selected].provider)} · ${_category(images[_selected].category)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocale.cancel.getString(context)),
            ),
            TextButton(
              onPressed: images?.isNotEmpty == true ? _choose : null,
              child: Text(AppLocale.select.getString(context)),
            ),
            FilledButton(
              onPressed: _pending.isEmpty ? null : _apply,
              child: Text(
                '${AppLocale.apply.getString(context)} (${_pending.length})',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
