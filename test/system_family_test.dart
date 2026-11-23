import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/ra_hash_policy.dart';
import 'package:neostation/models/system_configuration.dart';
import 'package:neostation/models/system_family.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/services/json_config_service.dart';
import 'package:neostation/utils/disc/dolphin_ra_hash.dart';
import 'package:neostation/utils/disc/ra_disc_hash.dart';

void main() {
  final definitions = Directory('assets/systems')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .map((file) {
        final definition =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final system = definition['system'] as Map<String, dynamic>;
        return SystemConfiguration(
          system: SystemModel.fromJson({
            'folderName': system['id'],
            'folders': system['folders'],
            'extensions': system['extensions'],
            'raId': system['ids']?['retroachievements'],
            'screenscraperId': system['ids']?['screenscraper'],
            'multidisc': system['multidisc'],
            'raHashAlgo': system['ra_hash']?['algo'],
            'raHashMode': system['ra_hash']?['mode'],
          }),
          emulators: [
            for (final emulator in (definition['emulators'] ?? []) as List)
              EmulatorDefinition.fromJson(emulator as Map<String, dynamic>),
          ],
        );
      })
      .toList();
  final resolved = {
    for (final definition in JsonConfigService.inheritHacksDefinitions(
      definitions,
    ))
      definition.system.folderName: definition,
  };

  for (final original in definitions.where(
    (config) => config.system.folderName.endsWith('-hacks'),
  )) {
    final id = original.system.folderName;
    final parentId = parentSystemId(id);
    test('$id inherits the effective $parentId definition', () {
      final child = resolved[id]!;
      final parent = resolved[parentId]!;
      expect(child.system.folders, original.system.folders);
      expect(child.system.raId, parent.system.raId);
      expect(child.system.screenscraperId, parent.system.screenscraperId);
      expect(child.system.extensions, parent.system.extensions);
      expect(child.system.raHashPolicy.algo, parent.system.raHashPolicy.algo);
      expect(child.system.raHashPolicy.isHashOnly, isTrue);
      expect(child.emulators.length, parent.emulators.length);
      for (final (index, emulator) in parent.emulators.indexed) {
        final inherited = child.emulators[index];
        expect(
          inherited.uniqueId,
          emulatorIdForSystem(emulator.uniqueId, parentId, id),
        );
        expect(inherited.platforms, emulator.platforms);
        expect(inherited.extensions, emulator.extensions);
        expect(inherited.isDefaultCore, emulator.isDefaultCore);
        expect(inherited.isDefaultStandalone, emulator.isDefaultStandalone);
        expect(
          inherited.isretroAchievementsCompatible,
          emulator.isretroAchievementsCompatible,
        );
      }
    });
  }

  test('GameCube and GameCube Hacks use the logical disc hashing policy', () {
    for (final id in ['gc', 'gc-hacks']) {
      expect(resolved[id]!.system.raId, '16');
      expect(resolved[id]!.system.raHashPolicy.algo, RaHashAlgo.gamecube);
    }
    expect(RaDiscHash.canHash('Game.RVZ', algo: RaHashAlgo.gamecube), isTrue);
    expect(RaDiscHash.canHash('Game.RVZ', algo: RaHashAlgo.psp), isFalse);
    expect(
      RaDiscHash.canHash('Invalid.dol', algo: RaHashAlgo.gamecube),
      isFalse,
    );
    expect(
      DolphinRaHash.parseOutput('15449523EAD65939970E336A91BF943B\n'),
      '15449523ead65939970e336a91bf943b',
    );
    expect(DolphinRaHash.parseOutput('verification failed'), isNull);
  });
}
