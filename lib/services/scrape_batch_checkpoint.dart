import 'dart:convert';
import 'dart:io';

import '../utils/atomic_file_writer.dart';
import 'logger_service.dart';

/// Records the work list once, then appends completed ROM paths per batch.
/// A crash during an append can cause the final path to be retried.
class ScrapeBatchCheckpoint {
  ScrapeBatchCheckpoint(this.file);

  final File file;
  static final _log = LoggerService.instance;

  Future<Set<String>?> remaining() async {
    try {
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      final queue = (jsonDecode(lines.first) as List).cast<String>().toSet();
      for (final line in lines.skip(1)) {
        try {
          final entry = jsonDecode(line);
          if (entry is List) queue.removeAll(entry.whereType<String>());
        } on FormatException {
          // A process can be interrupted before the last append is complete.
        }
      }
      return queue;
    } catch (error) {
      _log.w('Scrape checkpoint could not be read (${error.runtimeType})');
      return null;
    }
  }

  Future<void> begin(Set<String> paths) async {
    try {
      await writeFileAtomically(
        file,
        utf8.encode('${jsonEncode(paths.toList())}\n'),
      );
    } on FileSystemException catch (error) {
      _log.w('Scrape checkpoint could not be saved (${error.runtimeType})');
    }
  }

  Future<void> recordCompleted(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      // Start with a newline so a partial prior append cannot obscure this one.
      await file.writeAsString(
        '\n${jsonEncode(paths)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException catch (error) {
      _log.w('Scrape checkpoint could not be updated (${error.runtimeType})');
    }
  }

  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      _log.w('Scrape checkpoint could not be cleared (${error.runtimeType})');
    }
  }
}
