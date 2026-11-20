import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/app_locale.dart';
import '../models/artwork_scrape_event.dart';
import '../services/game_service.dart';
import '../utils/gamepad_nav.dart';

class ScrapingSummaryDialog extends StatefulWidget {
  const ScrapingSummaryDialog({
    super.key,
    required this.totalGames,
    required this.successfulGames,
    required this.failedGames,
    required this.elapsedTime,
    required this.imagesDownloaded,
    required this.imagesAssigned,
    required this.imagesSkippedManual,
    required this.issues,
    this.canRetry = false,
  });

  final int totalGames;
  final int successfulGames;
  final int failedGames;
  final String elapsedTime;
  final int imagesDownloaded;
  final int imagesAssigned;
  final int imagesSkippedManual;
  final List<ScrapeIssue> issues;
  final bool canRetry;

  @override
  State<ScrapingSummaryDialog> createState() => _ScrapingSummaryDialogState();
}

class _ScrapingSummaryDialogState extends State<ScrapingSummaryDialog> {
  static const _layer = 'scraping_summary_dialog';
  final _issueScroll = ScrollController();
  late final GamepadNavigation _gamepadNav;

  bool get _canRetry => widget.canRetry && widget.issues.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _gamepadNav = GamepadNavigation(
      onSelectItem: _close,
      onBack: _close,
      onXButton: _canRetry ? _retry : null,
      onNavigateUp: () => _scroll(-1),
      onNavigateDown: () => _scroll(1),
    );
    _gamepadNav.initialize();
    GamepadNavigationManager.pushLayer(
      _layer,
      onActivate: _gamepadNav.activate,
      onDeactivate: _gamepadNav.deactivate,
    );
  }

  void _close() => Navigator.of(context).pop(false);
  void _retry() => Navigator.of(context).pop(true);

  void _scroll(int direction) {
    if (!_issueScroll.hasClients) return;
    final position = _issueScroll.position;
    final target = (position.pixels + direction * 40.r).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _issueScroll.jumpTo(target);
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layer);
    _gamepadNav.dispose();
    _issueScroll.dispose();
    super.dispose();
  }

  String _category(String category) => switch (category) {
    'box2d' => AppLocale.boxart,
    'title_screens' => AppLocale.libretroTitleScreen,
    'screenshots' => AppLocale.screenshot,
    'wheels' => AppLocale.wheel,
    'icons' => AppLocale.galleryGameIcon,
    'fanarts' => AppLocale.fanart,
    'videos' => AppLocale.scrapeVideo,
    _ => AppLocale.media,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = [
      (AppLocale.totalGames, '${widget.totalGames}'),
      (
        AppLocale.successFailed,
        '${widget.successfulGames} / ${widget.failedGames}',
      ),
      (AppLocale.scrapeBatchDownloaded, '${widget.imagesDownloaded}'),
      (AppLocale.scrapeBatchAssigned, '${widget.imagesAssigned}'),
      (AppLocale.scrapeBatchManual, '${widget.imagesSkippedManual}'),
    ];
    return AlertDialog(
      title: Text(AppLocale.scrapingCompleted.getString(context)),
      content: SizedBox(
        width: 300.r,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in stats)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(label.getString(context))),
                  Text(value),
                ],
              ),
            Text(widget.elapsedTime, style: theme.textTheme.bodySmall),
            if (widget.issues.isNotEmpty) ...[
              const Divider(),
              Text(AppLocale.scrapeBatchIncomplete.getString(context)),
              SizedBox(
                height: 120.r,
                child: Scrollbar(
                  controller: _issueScroll,
                  child: ListView.builder(
                    controller: _issueScroll,
                    shrinkWrap: true,
                    itemCount: widget.issues.length,
                    itemBuilder: (context, index) {
                      final issue = widget.issues[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(issue.name),
                        subtitle: Text(
                          [
                            if (issue.gameFailed)
                              AppLocale.scrapeBatchFailed.getString(context),
                            for (final item in issue.categories.entries)
                              '${_category(item.key).getString(context)} · ${(item.value == ArtworkScrapeEvent.failed ? AppLocale.scrapeBatchFailed : AppLocale.scrapeBatchUnavailable).getString(context)}',
                          ].join('\n'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_canRetry)
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: Text('X · ${AppLocale.retry.getString(context)}'),
          ),
        FilledButton(
          onPressed: _close,
          child: Text(AppLocale.ok.getString(context)),
        ),
      ],
    );
  }
}
