import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Uses Dolphin's logical disc reader and its bundled rcheevos implementation.
/// Hashing the RVZ container bytes would produce an unrelated digest.
class DolphinRaHash {
  static const _extensions = {
    '.iso',
    '.gcm',
    '.rvz',
    '.wia',
    '.gcz',
    '.ciso',
    '.tgc',
  };

  static bool supports(String filename) =>
      _extensions.contains(path.extension(filename).toLowerCase());

  static String? parseOutput(String output) {
    final hash = output.trim();
    return RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hash)
        ? hash.toLowerCase()
        : null;
  }

  static Future<String?> compute(String filename) async {
    if (!supports(filename) || !Platform.isLinux) return null;

    final arguments = ['verify', '-a', 'rchash', '-i', filename];
    for (final (program, args) in [
      ('dolphin-tool', arguments),
      (
        'flatpak',
        [
          'run',
          '--command=dolphin-tool',
          'org.DolphinEmu.dolphin-emu',
          ...arguments,
        ],
      ),
    ]) {
      try {
        final process = await Process.start(program, args);
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.drain<void>();
        final exit = process.exitCode.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        final results = await Future.wait<Object?>([exit, stdout, stderr]);
        if (results[0] == 0) {
          final hash = parseOutput(results[1]! as String);
          if (hash != null) return hash;
        }
      } on ProcessException {
        // Try the other Dolphin installation method.
      }
    }
    return null;
  }
}
