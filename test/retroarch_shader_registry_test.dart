import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/visual_profiles/retroarch_shader_registry.dart';
import 'package:path/path.dart' as path;

void main() {
  test('discovers only compatible presets and resolves the same IDs', () async {
    final root = await Directory.systemTemp.createTemp('shader-registry-test');
    addTearDown(() => root.delete(recursive: true));
    final crt = await Directory(path.join(root.path, 'shaders_slang', 'crt'))
        .create(recursive: true);
    final file = await File(path.join(crt.path, 'crt-pi.slangp')).create();
    await File(path.join(root.path, 'old.glslp')).create();
    await File(path.join(root.path, 'cg.cgp')).create();
    final registry = RetroArchShaderRegistry(root, 'slang');
    final preset = (await registry.discover()).single;
    expect(preset.category, 'crt');
    expect(preset.matches('CRT Pi'), isTrue);
    expect(await registry.resolve(preset.id), file.path);
    expect(await registry.resolve('@crt'), file.path);
    expect(await registry.resolve('old.glslp'), isNull);
    expect(await registry.resolve(file.path), isNull);
    expect(RetroArchShaderRegistry.formatForDriver('vulkan'), 'slang');
    expect(RetroArchShaderRegistry.formatForDriver('gl'), 'glsl');
    expect(RetroArchShaderRegistry.formatForDriver('sdl2'), isNull);
  });

  test(
    'reads effective preset parameters and writes only bounded overrides',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'shader-parameters-test',
      );
      addTearDown(() => root.delete(recursive: true));
      await File(path.join(root.path, 'pass.slang')).writeAsString(
        '#pragma parameter SHARPNESS "Sharpness" 0.4 0.0 1.0 0.05\n',
      );
      await File(path.join(root.path, 'base.slangp')).writeAsString(
        'shaders = "1"\nshader0 = "pass.slang"\nSHARPNESS = "0.6"\n',
      );
      final userPreset = await File(path.join(root.path, 'user.slangp'))
          .writeAsString('#reference "base.slangp"\nSHARPNESS = "0.7"\n');
      final registry = RetroArchShaderRegistry(root, 'slang');
      final parameter = (await registry.parameters('user.slangp')).single;
      expect(parameter.name, 'Sharpness');
      expect(parameter.initial, 0.7);
      expect(parameter.step, 0.05);
      final scratch = await root.createTemp('session-');
      final output = await registry.withParameters('user.slangp', scratch, {
        'SHARPNESS': 2.5,
        'UNKNOWN': 0.5,
      });
      expect(await File(output!).readAsLines(), [
        '#reference "${userPreset.path}"',
        'SHARPNESS = "1.0"',
      ]);
      expect(await userPreset.readAsString(), contains('SHARPNESS = "0.7"'));
    },
  );
}
