import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/libretro_metadata_service.dart';

void main() {
  test('reads catalog comments and ignores conflicting releases', () {
    const dat = '''
clrmamepro (
  name "Nintendo"
)
game (
  comment "EarthBound (USA)"
  developer "HAL Laboratory"
  rom ( crc DC9BB451 )
)
game (
  name "Star Fox (USA)"
  developer "Nintendo"
)
game (
  name "Star Fox (USA)"
  developer "Other"
)
''';
    expect(LibretroMetadataService.parseDat(dat, 'developer'), {
      'earthbound (usa)': 'HAL Laboratory',
    });
  });

  test('accepts unquoted values in CRLF catalogs', () {
    const dat =
        'game (\r\n\tcomment "EarthBound (USA)"\r\n'
        '\treleaseyear 1995\r\n)\r\n';
    expect(LibretroMetadataService.parseDat(dat, 'releaseyear'), {
      'earthbound (usa)': '1995',
    });
  });
}
