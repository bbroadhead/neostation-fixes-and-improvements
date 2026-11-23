import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:http/http.dart' as http;
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/game_service.dart'
    show GamepadNavigationManager;
import 'package:neostation/services/steam_grid_db_artwork_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/login_form_selection.dart';

class SteamGridDbKeyDialog extends StatefulWidget {
  const SteamGridDbKeyDialog({super.key, this.client});

  final http.Client? client;

  @override
  State<SteamGridDbKeyDialog> createState() => _SteamGridDbKeyDialogState();
}

class _SteamGridDbKeyDialogState extends State<SteamGridDbKeyDialog>
    with LoginFormSelection<SteamGridDbKeyDialog> {
  static const _layerId = 'steam_grid_db_key_dialog';
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final GamepadNavigation _navigation;
  bool _busy = true;
  String? _error;
  bool _saved = false;

  @override
  List<FocusNode?> get selectionSlots => [_focus, null];

  @override
  void initState() {
    super.initState();
    attachFocusSelectionListeners();
    _navigation = GamepadNavigation(
      onNavigateUp: () => !_busy && moveSelection(-1),
      onNavigateDown: () => !_busy && moveSelection(1),
      onSelectItem: () {
        if (!_busy && !focusSelectedField()) _save();
      },
      onBack: () {
        if (isAnyFieldFocused()) {
          exitTextEntry();
        } else if (!_busy) {
          Navigator.of(context).pop();
        }
      },
      isTextFieldFocused: isAnyFieldFocused,
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
      final key = await SteamGridDbArtworkService.readSavedApiKey();
      if (!mounted) return;
      _controller.text = key ?? '';
    } catch (_) {
      if (!mounted) return;
      _error = AppLocale.credentialStorageUnavailable;
    }
    setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_busy) return;
    exitTextEntry();
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    final key = _controller.text.trim();
    try {
      if (key.isNotEmpty) {
        final failure = await SteamGridDbArtworkService.testConnection(
          key,
          client: widget.client,
        );
        if (!mounted) return;
        if (failure != null) {
          setState(
            () => _error = switch (failure) {
              SteamGridDbConnectionFailure.invalidKey =>
                AppLocale.rommErrorInvalidApiKey,
              SteamGridDbConnectionFailure.network =>
                AppLocale.steamGridDbNetworkError,
              SteamGridDbConnectionFailure.rateLimited =>
                AppLocale.steamGridDbRateLimited,
              SteamGridDbConnectionFailure.unavailable =>
                AppLocale.steamGridDbUnavailable,
              SteamGridDbConnectionFailure.unexpectedResponse =>
                AppLocale.steamGridDbUnexpectedResponse,
            },
          );
          return;
        }
      }
      await SteamGridDbArtworkService.saveApiKey(key);
      if (!mounted) return;
      if (key.isEmpty) {
        Navigator.of(context).pop();
      } else {
        setState(() => _saved = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppLocale.failedToSaveSetting);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layerId);
    _navigation.dispose();
    detachFocusSelectionListeners();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(AppLocale.steamGridDbApiKey.getString(context)),
      scrollable: true,
      content: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: !_busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {
          _saved = false;
          _error = null;
        }),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: AppLocale.rommApiKey.getString(context),
          errorText: _error?.getString(context),
          errorMaxLines: 3,
          helperText: _saved
              ? AppLocale.rommConnectionSuccess.getString(context)
              : null,
          helperStyle: TextStyle(color: colors.primary),
          border: OutlineInputBorder(
            borderSide: BorderSide(
              color: isSelected(0) ? colors.primary : colors.outline,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: isSelected(0) ? colors.primary : colors.outline,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(
            (_saved ? AppLocale.close : AppLocale.cancel).getString(context),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          style: TextButton.styleFrom(
            backgroundColor: isSelected(1) ? colors.primaryContainer : null,
          ),
          child: Text(AppLocale.save.getString(context)),
        ),
      ],
    );
  }
}
