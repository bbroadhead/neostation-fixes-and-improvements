import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/retro_achievements_provider.dart';
import '../../repositories/game_repository.dart';
import '../../repositories/retro_achievements_repository.dart';
import '../../services/retro_achievements_service.dart';
import '../../utils/ra_coverage.dart';

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

Future<void> openRaCompatibilityReview(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RaIncompatibleGamesScreen(
          title: AppLocale.raCompatibilityHome.getString(context),
          openDetails: (game) => _showCompatibilityEvidence(context, game),
          loadGames: _loadCompatibilityReview,
        ),
      ),
    );

Future<List<IncompatibleGame>> _loadCompatibilityReview({
  bool Function()? isCancelled,
}) async {
  final review = <IncompatibleGame>[];
  final rows = await GameRepository.getAllGames();
  for (final (index, row) in rows.indexed) {
    if (index % 32 == 0) await Future<void>.delayed(Duration.zero);
    if (isCancelled?.call() == true) return const [];
    if (!isRaSupportedSystem(row.systemRaId) || row.romPath.isEmpty) continue;
    final reason = (await RetroAchievementsRepository.getRomCompatibility(
      row.romPath,
    )).status;
    if (reason != RaCompatibilityStatus.supported) {
      review.add((game: GameModel.fromDatabaseModel(row), reason: reason));
    }
  }
  return review;
}

/// Official filenames are the only language evidence available in the hash API.
int? englishRevisionOrder(String filename) {
  final name = filename.toLowerCase();
  final tags = RegExp(r'\(([^)]+)\)|\[([^\]]+)\]')
      .allMatches(name)
      .map((match) => match[1] ?? match[2]!)
      .join(' ');
  if (RegExp(r'\bt\+\s*en\b').hasMatch(tags) ||
      (RegExp(r'\benglish\b').hasMatch(tags) &&
          RegExp(r'\b(translated|translation)\b').hasMatch(tags))) {
    return 3;
  }
  if (RegExp(r'\b(usa|united states)\b').hasMatch(tags)) return 0;
  final english = RegExp(r'\b(english|en)\b').hasMatch(tags);
  if (english && tags.contains('europe')) return 1;
  if (english && (tags.contains('world') || tags.contains('international'))) {
    return 2;
  }
  return null;
}

Future<void> _showCompatibilityEvidence(
  BuildContext context,
  GameModel game,
) async {
  final provider = context.read<RetroAchievementsProvider?>();
  final compatibility = await RetroAchievementsRepository.getRomCompatibility(
    game.romPath!,
  );
  if (!context.mounted) return;
  final gameId = compatibility.gameId ?? game.idRa;
  final files = gameId == null || (provider?.apiKey.isEmpty ?? true)
      ? Future<List<({String hash, String name})>?>.value(null)
      : RetroAchievementsService.getSupportedGameFiles(
          gameId,
          apiKey: provider!.apiKey,
        );
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(game.name),
        content: SizedBox(
          width: 510,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(game.systemRealName ?? game.systemFolderName ?? ''),
                Text(compatibility.status.labelKey.getString(context)),
                Text(AppLocale.raHash.getString(context)),
                SelectableText(
                  game.raHash ?? AppLocale.unknown.getString(context),
                ),
                const SizedBox(height: 12),
                Text(AppLocale.raSupportedFiles.getString(context)),
                FutureBuilder(
                  future: files,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    final rows = snapshot.data;
                    if (rows == null) {
                      return Text(
                        AppLocale.raSupportedFilesUnavailable.getString(
                          context,
                        ),
                      );
                    }
                    final english =
                        rows
                            .where(
                              (row) => englishRevisionOrder(row.name) != null,
                            )
                            .toList()
                          ..sort(
                            (a, b) =>
                                englishRevisionOrder(a.name)!
                                    .compareTo(englishRevisionOrder(b.name)!),
                          );
                    if (english.isEmpty) {
                      return Text(
                        AppLocale.raNoVerifiedEnglishHash.getString(context),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final row in english)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.name),
                                SelectableText(row.hash),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (gameId != null && gameId > 0)
            TextButton(
              onPressed: () async {
                await launchUrl(
                  Uri.https('retroachievements.org', '/game/$gameId'),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: Text(AppLocale.raOpenPage.getString(context)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocale.close.getString(context)),
          ),
        ],
      );
    },
  );
}

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
    RaCompatibilityStatus.unknown,
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
  bool _ascending = true;
  String _query = '';
  String? _system;
  final _searchFocus = FocusNode();

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
      onBack: () {
        if (_searchFocus.hasFocus) {
          _searchFocus.unfocus();
        } else {
          Navigator.of(context).maybePop();
        }
      },
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
    _searchFocus.dispose();
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
        if (!games.any((entry) => entry.game.systemRealName == _system)) {
          _system = null;
        }
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
    _visible =
        _games.where((entry) {
          final game = entry.game;
          return (reason == null || entry.reason == reason) &&
              (_system == null || _system == game.systemRealName) &&
              ('${game.name} ${game.raHash ?? ''}'.toLowerCase().contains(
                _query,
              ));
        }).toList()..sort((a, b) {
          final result = a.game.name.toLowerCase().compareTo(
            b.game.name.toLowerCase(),
          );
          return _ascending ? result : -result;
        });
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: AppLocale.searchNameHint.getString(context),
                    ),
                    onChanged: (value) => setState(() {
                      _query = value.trim().toLowerCase();
                      _updateVisible(null);
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _system ?? '',
                  onChanged: (value) => setState(() {
                    _system = (value?.isEmpty ?? true) ? null : value;
                    _updateVisible(null);
                  }),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(AppLocale.allContent.getString(context)),
                    ),
                    for (final name
                        in (_games
                            .map((entry) => entry.game.systemRealName)
                            .whereType<String>()
                            .toSet()
                            .toList()
                          ..sort()))
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                  tooltip:
                      (_ascending
                              ? AppLocale.sortNameDesc
                              : AppLocale.sortNameAsc)
                          .getString(context),
                  onPressed: () => setState(() {
                    _ascending = !_ascending;
                    _updateVisible(null);
                  }),
                ),
              ],
            ),
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
          subtitle: Text(
            [
              ?entry.game.systemRealName,
              entry.reason.labelKey.getString(context),
              ?entry.game.raHash,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
