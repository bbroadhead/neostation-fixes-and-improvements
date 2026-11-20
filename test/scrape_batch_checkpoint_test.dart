import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/scrape_batch_checkpoint.dart';

void main() {
  test(
    'resumes only unfinished ROM paths after a torn checkpoint append',
    () async {
      final temp = await Directory.systemTemp.createTemp('scrape-checkpoint-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/checkpoint.jsonl');
      final batch = ScrapeBatchCheckpoint(file);
      expect(await batch.remaining(), isNull);
      await batch.begin({'/games/a.nes', '/games/b.nes', '/games/c.nes'});
      await batch.recordCompleted(['/games/a.nes']);
      await file.writeAsString('["/games/b.ne', mode: FileMode.append);

      final resumed = ScrapeBatchCheckpoint(file);
      expect(await resumed.remaining(), {'/games/b.nes', '/games/c.nes'});
      await resumed.recordCompleted(['/games/b.nes']);
      expect(await resumed.remaining(), {'/games/c.nes'});
      await resumed.clear();
      expect(await resumed.remaining(), isNull);
    },
  );
}
