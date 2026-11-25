import 'package:neostation/utils/artwork_title.dart';
import 'package:test/test.dart';

void main() {
  test('removes dump metadata while retaining alternate edition evidence', () {
    expect(ArtworkTitle.clean('A Game (USA) (Rev 2) [!]'), 'A Game');
    expect(
      ArtworkTitle.clean('A Game [English Translation] (Japan)'),
      'A Game [English Translation]',
    );
    expect(
      ArtworkTitle.normalized('A Game [Hack]'),
      isNot(ArtworkTitle.normalized('A Game')),
    );
    expect(
      ArtworkTitle.normalized('A Game (Special Edition)'),
      isNot(ArtworkTitle.normalized('A Game')),
    );
  });

  test('keeps localized Dragon Quest and Warrior search aliases', () {
    expect(
      ArtworkTitle.queries("Dragon Quest Monsters 2 - Tara’s Adventure (USA)"),
      contains("Dragon Warrior Monsters 2: Tara’s Adventure"),
    );
    expect(
      ArtworkTitle.queries('Dragon Warrior IV (USA)'),
      contains('Dragon Quest IV'),
    );
  });
}
