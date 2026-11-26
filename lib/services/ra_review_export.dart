import 'dart:convert';
import 'dart:typed_data';

import '../models/ra_compatibility.dart';

typedef RaReportRow = ({
  String title,
  String system,
  String? romHash,
  RaCompatibilityStatus status,
  int? gameId,
  List<({String hash, String name})>? verifiedFiles,
  DateTime? catalogueRefreshedAt,
});

Uint8List encodeRaReviewCsv(Iterable<RaReportRow> report) {
  String cell(String value) {
    final dangerous = RegExp(r'^[\s]*[=+@-]|^[\t\r\n]').hasMatch(value);
    final text = dangerous ? "'$value" : value;
    return '"${text.replaceAll('"', '""')}"';
  }

  const header = [
    'Game title',
    'System',
    'Current ROM hash',
    'Matching status',
    'Verified compatible hashes',
    'Compatible ROM versions',
    'RetroAchievements game ID',
    'RetroAchievements URL',
    'Catalogue refreshed (UTC)',
  ];

  final output = StringBuffer();
  void writeRow(List<String> values) {
    output.write(values.map(cell).join(','));
    output.write('\r\n');
  }

  writeRow(header);
  for (final row in report) {
    final files = row.verifiedFiles;
    final id = row.gameId;
    writeRow([
      row.title,
      row.system,
      row.romHash ?? '',
      row.status.name,
      files?.map((file) => file.hash).join(' | ') ?? '',
      files?.map((file) => file.name).join(' | ') ?? '',
      id?.toString() ?? '',
      if (id != null && id > 0)
        'https://retroachievements.org/game/$id'
      else
        '',
      row.catalogueRefreshedAt?.toUtc().toIso8601String() ?? '',
    ]);
  }
  return Uint8List.fromList(utf8.encode(output.toString()));
}
