import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../l10n/app_locale.dart';
import '../../models/game_model.dart';
import '../../models/ra_compatibility.dart';
import '../../services/collections/collections_service.dart';
import '../../services/gamepad/gamepad_navigation_manager.dart';
import '../../utils/gamepad_nav.dart';
import '../../utils/ra_compatibility_labels.dart';

typedef IncompatibleGame = ({GameModel game, RaCompatibilityStatus reason});

/// Review the current reasons for the generated collection.
class RaIncompatibleGamesScreen extends StatefulWidget {
  const RaIncompatibleGamesScreen({
    super.key,
    required this.title,
    required this.openDetails,
    this.loadGames = CollectionsService.loadIncompatibleGames,
  });

  final String title;
  final Future<void> Function(GameModel) openDetails;
  final Future<List<IncompatibleGame>> Function({bool Function()? isCancelled})
  loadGames;

  @override
  State<RaIncompatibleGamesScreen> createState() =>
      _RaIncompatibleGamesScreenState();
}

class _RaIncompatibleGamesScreenState extends State<RaIncompatibleGamesScreen> {
  static const _filters = [
    null,
    RaCompatibilityStatus.differentRomRequired,
    RaCompatibilityStatus.noAchievementSet,
  ];
  late final _layer = 'ra_incompatible_games#${identityHashCode(this)}';
  late final GamepadNavigation _navigation;
  final _scroll = ScrollController();

  List<IncompatibleGame> _games = const [];
  List<IncompatibleGame> _visible = const [];
  int _selected = 0;
  int _filter = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _opening = false;

  double get _rowHeight => 43.r;

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onLeftBumper: () => _selectFilter((_filter - 1) % _filters.length),
      onRightBumper: () => _selectFilter((_filter + 1) % _filters.length),
      onSelectItem: () {
        if (_loadFailed) {
          _load();
        } else if (_visible.isNotEmpty) {
          _open(_visible[_selected].game);
        }
      },
      onBack: () => Navigator.of(context).maybePop(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigation.initialize();
      GamepadNavigationManager.pushLayer(
        _layer,
        onActivate: _navigation.activate,
        onDeactivate: _navigation.deactivate,
      );
    });
    _load();
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _navigation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({String? preserveRomPath}) async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final games = await widget.loadGames(isCancelled: () => !mounted);
      if (!mounted) return;
      setState(() {
        _games = games;
        _updateVisible(preserveRomPath);
        _loading = false;
      });
      _revealSelection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _updateVisible(String? preserveRomPath) {
    final reason = _filters[_filter];
    _visible = reason == null
        ? _games
        : _games.where((entry) => entry.reason == reason).toList();
    final index = preserveRomPath == null
        ? -1
        : _visible.indexWhere((entry) => entry.game.romPath == preserveRomPath);
    _selected = index < 0 ? 0 : index;
  }

  void _selectFilter(int index) {
    if (_filter == index || _loading || _loadFailed) return;
    setState(() {
      _filter = index;
      _updateVisible(null);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int step) {
    if (_visible.isEmpty || _loading || _loadFailed) return;
    setState(
      () => _selected = (_selected + step).clamp(0, _visible.length - 1),
    );
    _revealSelection();
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final top = _selected * _rowHeight;
      final bottom = top + _rowHeight;
      if (top < position.pixels) {
        _scroll.jumpTo(top);
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (bottom - position.viewportDimension).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  Future<void> _open(GameModel game) async {
    if (_opening || _loading || _loadFailed) return;
    _opening = true;
    try {
      await widget.openDetails(game);
      if (mounted) await _load(preserveRomPath: game.romPath);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.r, vertical: 8.r),
        child: Column(
          children: [
            Wrap(
              spacing: 8.r,
              runSpacing: 4.r,
              children: [
                for (final (index, reason) in _filters.indexed)
                  ChoiceChip(
                    label: Text(
                      (reason?.labelKey ?? AppLocale.allContent).getString(
                        context,
                      ),
                    ),
                    selected: _filter == index,
                    onSelected: (_) => _selectFilter(index),
                  ),
              ],
            ),
            SizedBox(height: 8.r),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocale.collectionLoadError.getString(context)),
            TextButton(
              onPressed: _load,
              child: Text(AppLocale.retry.getString(context)),
            ),
          ],
        ),
      );
    }
    if (_visible.isEmpty) {
      return Center(child: Text(AppLocale.emptyCollection.getString(context)));
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _visible.length,
      itemExtent: _rowHeight,
      itemBuilder: (context, index) {
        final entry = _visible[index];
        return ListTile(
          dense: true,
          selected: index == _selected,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          title: Text(
            entry.game.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(entry.reason.labelKey.getString(context)),
          trailing: Tooltip(
            message: AppLocale.gameInfo.getString(context),
            child: const Icon(Icons.info_outline),
          ),
          onTap: () {
            setState(() => _selected = index);
            _open(entry.game);
          },
        );
      },
    );
  }
}
