import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/retro_achievements_provider.dart';
import '../../repositories/game_repository.dart';
import '../../repositories/retro_achievements_repository.dart';
import '../../services/retro_achievements_service.dart';
import '../../services/ra_review_export.dart';
import '../../providers/sqlite_config_provider.dart';
import '../game_screen/game_details_card/dialogs/ra_match_picker_dialog.dart';
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
import '../../widgets/tv_directory_picker.dart';

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
    review.add((game: GameModel.fromDatabaseModel(row), reason: reason));
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
  final system = context
      .read<SqliteConfigProvider?>()
      ?.detectedSystems
      .where(
        (system) =>
            system.id == game.systemId ||
            system.folderName == game.systemFolderName,
      )
      .firstOrNull;
  final source = await RetroAchievementsRepository.getRomRaMatchSource(
    game.romPath!,
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return _RaReviewActions(
        title: game.name,
        content: SizedBox(
          width: 510,
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
                      AppLocale.raSupportedFilesUnavailable.getString(context),
                    );
                  }
                  final ordered = [...rows]
                    ..sort((a, b) {
                      final priority = (englishRevisionOrder(a.name) ?? 4)
                          .compareTo(englishRevisionOrder(b.name) ?? 4);
                      return priority != 0
                          ? priority
                          : a.name.compareTo(b.name);
                    });
                  final hasEnglish = ordered.any(
                    (row) => englishRevisionOrder(row.name) != null,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!hasEnglish)
                        Text(
                          AppLocale.raNoVerifiedEnglishHash.getString(context),
                        ),
                      for (final row in ordered)
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
        actions: [
          if (game.raHash case final hash?)
            (
              AppLocale.raReportCopyHash.getString(context),
              () async {
                await Clipboard.setData(ClipboardData(text: hash));
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocale.raReportHashCopied.getString(context),
                      ),
                    ),
                  );
                }
              },
            ),
          if (system != null)
            (
              AppLocale.raReportManualMatch.getString(context),
              () async {
                final changed = await RaMatchPickerDialog.show(
                  context,
                  game: game,
                  system: system,
                  currentGameId: gameId,
                  isManualMatch:
                      source == RetroAchievementsRepository.raMatchManual,
                );
                if (changed && context.mounted) Navigator.pop(context);
              },
            ),
          if (gameId != null && gameId > 0)
            (
              AppLocale.raOpenPage.getString(context),
              () async {
                await launchUrl(
                  Uri.https('retroachievements.org', '/game/$gameId'),
                  mode: LaunchMode.externalApplication,
                );
              },
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
    RaCompatibilityStatus.hashFailed,
    RaCompatibilityStatus.verificationUnavailable,
    RaCompatibilityStatus.supported,
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
  bool _exporting = false;
  int? _headerFocus;
  String _query = '';
  String? _system;
  final _searchFocus = FocusNode();

  double get _rowHeight => 43.r;

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateUp: () {
        if (_headerFocus == null && _selected > 0 && _visible.isNotEmpty) {
          _move(-1);
        } else {
          setState(() => _headerFocus ??= 0);
        }
      },
      onNavigateDown: () {
        if (_headerFocus != null) {
          setState(() => _headerFocus = null);
        } else {
          _move(1);
        }
      },
      onNavigateLeft: () => _moveHeader(-1),
      onNavigateRight: () => _moveHeader(1),
      isTextFieldFocused: () => _searchFocus.hasFocus,
      onLeftTrigger: () => _page(-1),
      onRightTrigger: () => _page(1),
      onLeftBumper: () => _selectFilter((_filter - 1) % _filters.length),
      onRightBumper: () => _selectFilter((_filter + 1) % _filters.length),
      onSelectItem: () {
        if (_headerFocus case final header?) {
          switch (header) {
            case 0:
              _searchFocus.requestFocus();
            case 1:
              _cycleSystem();
            case 2:
              _toggleSort();
            case 3:
              _refresh();
            case 4:
              _chooseExport();
          }
        } else if (_loadFailed) {
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
          return (reason == null
                  ? entry.reason != RaCompatibilityStatus.supported
                  : entry.reason == reason) &&
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

  void _refresh() {
    if (_loading) return;
    _load(preserveRomPath: _visible.elementAtOrNull(_selected)?.game.romPath);
  }

  void _page(int direction) {
    if (_headerFocus != null || _searchFocus.hasFocus || !_scroll.hasClients) {
      return;
    }
    final page = (_scroll.position.viewportDimension / _rowHeight).floor();
    _move(direction * (page > 1 ? page - 1 : 1));
  }

  void _move(int step) {
    if (_visible.isEmpty || _loading || _loadFailed) return;
    setState(
      () => _selected = (_selected + step).clamp(0, _visible.length - 1),
    );
    _revealSelection();
  }

  List<String> get _systems => [
    '',
    ...(_games
        .map((entry) => entry.game.systemRealName)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort()),
  ];

  void _moveHeader(int step) {
    if (_headerFocus == null) return;
    setState(() => _headerFocus = (_headerFocus! + step) % 5);
  }

  void _cycleSystem() {
    final systems = _systems;
    _selectSystem(
      systems[(systems.indexOf(_system ?? '') + 1) % systems.length],
    );
  }

  void _selectSystem(String? value) {
    setState(() {
      _system = (value?.isEmpty ?? true) ? null : value;
      _updateVisible(null);
    });
    _revealSelection();
  }

  void _toggleSort() {
    final current = _visible.elementAtOrNull(_selected)?.game.romPath;
    setState(() {
      _ascending = !_ascending;
      _updateVisible(current);
    });
    _revealSelection();
  }

  Future<void> _chooseExport() async {
    if (_exporting || _loading || _loadFailed) return;
    final all = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RaReviewActions(
        title: AppLocale.raReportExport.getString(dialogContext),
        actions: [
          (
            AppLocale.raReportFiltered.getString(dialogContext),
            () => Navigator.pop(dialogContext, false),
          ),
          (
            AppLocale.raReportAll.getString(dialogContext),
            () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (all == null) {
      _exportMessage(AppLocale.raReportCancelled);
      return;
    }
    await _export(
      all
          ? _games
                .where(
                  (entry) => entry.reason != RaCompatibilityStatus.supported,
                )
                .toList(growable: false)
          : _visible,
    );
  }

  void _exportMessage(String key, {String? value, SnackBarAction? action}) {
    if (!mounted) return;
    final message = key.getString(context).replaceFirst('{value}', value ?? '');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _export(List<IncompatibleGame> selection) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    _exportMessage(AppLocale.raReportStarted);
    final apiKey = context.read<RetroAchievementsProvider?>()?.apiKey ?? '';
    try {
      final String? destination;
      if (Platform.isLinux) {
        destination = await TvDirectoryPicker.show(context);
        if (destination == null) {
          _exportMessage(AppLocale.raReportCancelled);
          return;
        }
      } else {
        destination = null;
      }
      final rows = <RaReportRow>[];
      final verified = <int, List<({String hash, String name})>?>{};
      for (final entry in selection.toList(growable: false)) {
        if (!mounted) return;
        final game = entry.game;
        final romPath = game.romPath;
        final compatibility = romPath == null
            ? null
            : await RetroAchievementsRepository.getRomCompatibility(romPath);
        final gameId = compatibility?.gameId ?? game.idRa;
        if (apiKey.isNotEmpty &&
            gameId != null &&
            gameId > 0 &&
            !verified.containsKey(gameId)) {
          verified[gameId] =
              await RetroAchievementsService.getSupportedGameFiles(
                gameId,
                apiKey: apiKey,
              );
        }
        rows.add((
          title: game.name,
          system: game.systemRealName ?? game.systemFolderName ?? '',
          romHash: game.raHash,
          status: compatibility?.status ?? entry.reason,
          gameId: gameId,
          verifiedFiles: verified[gameId],
          catalogueRefreshedAt: compatibility?.catalogueRefreshedAt,
        ));
      }
      if (!mounted) return;
      final bytes = encodeRaReviewCsv(rows);
      final Uri? saved;
      if (destination != null) {
        final time = DateTime.now().toUtc().microsecondsSinceEpoch;
        final file = File(
          path.join(
            destination,
            'neostation-retroachievements-review-$time.csv',
          ),
        );
        await file.create(exclusive: true);
        try {
          await file.writeAsBytes(bytes, flush: true);
        } on FileSystemException {
          try {
            await file.delete();
          } on FileSystemException {
            // Report the write failure even if cleanup also fails.
          }
          rethrow;
        }
        saved = file.uri;
      } else {
        saved = await FilePicker.saveFile(
          fileName: 'neostation-retroachievements-review.csv',
          bytes: bytes,
          mimeType: 'text/csv',
          dialogTitle: AppLocale.raReportExport.getString(context),
        );
      }
      if (!mounted) return;
      final savedUri = saved;
      if (savedUri == null) {
        _exportMessage(AppLocale.raReportCancelled);
      } else {
        final path = savedUri.scheme == 'file'
            ? savedUri.toFilePath()
            : savedUri.toString();
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => _RaReviewActions(
            title: AppLocale.raReportExport.getString(dialogContext),
            content: SizedBox(
              width: 510,
              child: SelectableText(
                AppLocale.raReportSaved
                    .getString(dialogContext)
                    .replaceFirst('{value}', path),
              ),
            ),
            actions: [
              if (savedUri.scheme == 'file')
                (
                  AppLocale.raReportOpenFolder.getString(dialogContext),
                  () async {
                    final opened = await launchUrl(
                      savedUri.resolve('.'),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && mounted) {
                      _exportMessage(
                        AppLocale.raReportFailed,
                        value: AppLocale.raReportOpenFolder.getString(context),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      }
    } catch (error) {
      _exportMessage(
        AppLocale.raReportFailed,
        value: error.runtimeType.toString(),
        action: mounted
            ? SnackBarAction(
                label: AppLocale.retry.getString(context),
                onPressed: () => _export(selection),
              )
            : null,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: AppLocale.refresh.getString(context),
            onPressed: _loading ? null : _refresh,
            color: _headerFocus == 3
                ? Theme.of(context).colorScheme.primary
                : null,
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(
              onPressed: _loading || _loadFailed || _exporting
                  ? null
                  : _chooseExport,
              style: _headerFocus == 4
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                    )
                  : null,
              icon: const Icon(Icons.download),
              label: Text(AppLocale.raReportExport.getString(context)),
            ),
          ),
        ],
      ),
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
                      filled: _headerFocus == 0,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value.trim().toLowerCase();
                        _updateVisible(null);
                      });
                      _revealSelection();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _system ?? '',
                  onChanged: _selectSystem,
                  focusColor: _headerFocus == 1
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  selectedItemBuilder: (context) => [
                    for (final name in _systems)
                      Center(
                        child: Text(
                          name.isEmpty
                              ? AppLocale.allContent.getString(context)
                              : name,
                          style: TextStyle(
                            fontWeight: _headerFocus == 1
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                  ],
                  items: [
                    for (final name in _systems)
                      DropdownMenuItem(
                        value: name,
                        child: Text(
                          name.isEmpty
                              ? AppLocale.allContent.getString(context)
                              : name,
                        ),
                      ),
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
                  onPressed: _toggleSort,
                  isSelected: _headerFocus == 2,
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
                      (reason?.labelKey ?? AppLocale.raReportAll).getString(
                        context,
                      ),
                    ),
                    selected: _filter == index,
                    onSelected: (_) => _selectFilter(index),
                  ),
              ],
            ),
            SizedBox(height: 8.r),
            if (_loading && _games.isNotEmpty) const LinearProgressIndicator(),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading && _games.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
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
          selected: _headerFocus == null && index == _selected,
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
            setState(() {
              _selected = index;
              _headerFocus = null;
            });
            _open(entry.game);
          },
        );
      },
    );
  }
}

class _RaReviewActions extends StatefulWidget {
  const _RaReviewActions({
    required this.title,
    this.content,
    required this.actions,
  });

  final String title;
  final Widget? content;
  final List<(String, VoidCallback)> actions;

  @override
  State<_RaReviewActions> createState() => _RaReviewActionsState();
}

class _RaReviewActionsState extends State<_RaReviewActions> {
  late final _layer = 'ra_review_actions#${identityHashCode(this)}';
  late final GamepadNavigation _navigation;
  final _scroll = ScrollController();
  int _selected = 0;

  void _move(int step) => setState(
    () => _selected = (_selected + step) % (widget.actions.length + 1),
  );

  void _scrollBy(double delta) {
    if (widget.content == null) {
      _move(delta > 0 ? 1 : -1);
    } else if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  void _close() => Navigator.pop(context);

  @override
  void initState() {
    super.initState();
    _navigation = GamepadNavigation(
      onNavigateLeft: () => _move(-1),
      onNavigateRight: () => _move(1),
      onNavigateUp: () => _scrollBy(-65),
      onNavigateDown: () => _scrollBy(65),
      onSelectItem: () => _selected == widget.actions.length
          ? _close()
          : widget.actions[_selected].$2(),
      onBack: _close,
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
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _navigation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: widget.content == null
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              controller: _scroll,
              child: widget.content,
            ),
          ),
    actions: [
      for (final (index, action) in [
        ...widget.actions,
        (AppLocale.close.getString(context), _close),
      ].indexed)
        TextButton(
          style: index == _selected
              ? TextButton.styleFrom(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                )
              : null,
          onPressed: action.$2,
          child: Text(action.$1),
        ),
    ],
  );
}
