import 'dart:convert';

import 'package:neostation/models/ra_compatibility.dart';
import 'package:neostation/services/ra_review_export.dart';
import 'package:test/test.dart';

void main() {
  test('exports verified revisions, quotes fields and keeps missing evidence blank', () {
    const hash = '0123456789abcdef0123456789abcdef';
    final csv = utf8.decode(
      encodeRaReviewCsv([
        (
          title: '=GAME("A", "B")',
          system: 'Nintendo DS',
          romHash: hash,
          status: RaCompatibilityStatus.differentRomRequired,
          gameId: 123,
          verifiedFiles: [(hash: hash, name: 'Game (USA), Rev 1')],
          catalogueRefreshedAt: DateTime.utc(2026, 11, 25),
        ),
        (
          title: 'Unresolved game',
          system: 'Atari Lynx',
          romHash: null,
          status: RaCompatibilityStatus.unknown,
          gameId: null,
          verifiedFiles: null,
          catalogueRefreshedAt: null,
        ),
      ]),
    );
    expect(
      csv,
      contains(
        '"'
        "'"
        '=GAME(""A"", ""B"")"',
      ),
    );
    expect(csv, contains('"differentRomRequired","$hash","Game (USA), Rev 1"'));
    expect(csv, contains('"123","https://retroachievements.org/game/123"'));
    expect(
      csv,
      contains('"Unresolved game","Atari Lynx","","unknown","","","","",""'),
    );
    expect(csv, endsWith('\r\n'));
  });
}
