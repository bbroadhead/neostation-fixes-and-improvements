import 'dart:io';

import 'package:path/path.dart' as path;

class RetroArchShaderParameter {
  const RetroArchShaderParameter({
    required this.id,
    required this.name,
    required this.minimum,
    required this.maximum,
    required this.initial,
    required this.step,
  });

  final String id;
  final String name;
  final double minimum;
  final double maximum;
  final double initial;
  final double step;
}

class RetroArchShaderPreset {
  const RetroArchShaderPreset({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final String category;

  bool matches(String query) {
    final haystack = '$name $category $id'.toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(haystack.contains);
  }
}

/// The same installed preset IDs are used in the editor and at launch.
class RetroArchShaderRegistry {
  const RetroArchShaderRegistry(this.directory, this.format);

  final Directory directory;
  final String format;

  static String? formatForDriver(String? driver) => switch (driver) {
    'vulkan' || 'glcore' => 'slang',
    'gl' => 'glsl',
    _ => null,
  };

  String? _builtinPath(String id) {
    final preset = switch ((id, format)) {
      ('@sharp', 'slang') => 'pixel-art-scaling/sharp-bilinear-simple',
      ('@sharp', 'glsl') => 'interpolation/sharp-bilinear-simple',
      ('@enhanced', 'slang') => 'interpolation/jinc2-sharp',
      ('@enhanced', 'glsl') => 'interpolation/sharp-bilinear-simple',
      ('@lcd', _) => 'handheld/lcd-grid-v2',
      ('@crt', _) => 'crt/crt-pi',
      _ => null,
    };
    if (preset == null) return null;
    return 'shaders_$format/$preset.${format}p';
  }

  String? previewPreset(String? id) {
    for (final preset in ['@sharp', '@lcd', '@crt']) {
      if (id != null && (id == preset || id == _builtinPath(preset))) {
        return preset;
      }
    }
    return null;
  }

  Future<String?> resolve(String id) async {
    final relative = id.startsWith('@') ? _builtinPath(id) : id;
    if (relative == null ||
        path.isAbsolute(relative) ||
        path.extension(relative).toLowerCase() != '.${format}p') {
      return null;
    }
    final file = File(path.join(directory.path, relative));
    try {
      if (!await file.exists()) return null;
      final canonical = await file.resolveSymbolicLinks();
      return path.isWithin(await directory.resolveSymbolicLinks(), canonical)
          ? canonical
          : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<List<RetroArchShaderPreset>> discover() async {
    if (!await directory.exists()) return [];
    final presets = <RetroArchShaderPreset>[];
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            path.extension(entity.path).toLowerCase() != '.${format}p') {
          continue;
        }
        final id = path.relative(entity.path, from: directory.path);
        final segments = path.split(id);
        final category = segments
            .take(segments.length - 1)
            .where((segment) => !segment.startsWith('shaders_'))
            .firstOrNull;
        presets.add(
          RetroArchShaderPreset(
            id: id,
            name: path.basenameWithoutExtension(id),
            category: category ?? '',
          ),
        );
      }
    } on FileSystemException {
      // Keep presets from readable directories when an installed pack is absent.
    }
    return presets..sort((a, b) {
      final categoryOrder = a.category.compareTo(b.category);
      if (categoryOrder != 0) return categoryOrder;
      final nameOrder = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return nameOrder != 0 ? nameOrder : a.id.compareTo(b.id);
    });
  }

  Future<List<RetroArchShaderParameter>> parameters(String id) async {
    final filename = await resolve(id);
    if (filename == null) return [];
    final root = await directory.resolveSymbolicLinks();
    final seen = <String>{};
    final declarations = <String, RetroArchShaderParameter>{};
    final defaults = <String, double>{};
    final fileReference = RegExp(
      r'^\s*(?:#(?:reference|include)\s+|shader\d+\s*=\s*)"([^"]+)"',
    );
    final pragma = RegExp(
      r'^\s*#pragma\s+parameter\s+(\w+)\s+"([^"]+)"\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(\S+))?',
    );
    final setting = RegExp(r'^\s*(\w+)\s*=\s*"?([^"\s]+)');
    Future<void> visit(File file) async {
      if (seen.length >= 64) return;
      try {
        final canonical = await file.resolveSymbolicLinks();
        if (!path.isWithin(root, canonical) ||
            !seen.add(canonical) ||
            await file.length() > 1024 * 1024) {
          return;
        }
        final lines = await file.readAsLines();
        for (final line in lines) {
          final reference = fileReference.firstMatch(line)?[1];
          if (reference != null) {
            await visit(File(path.join(path.dirname(canonical), reference)));
          }
        }
        for (final line in lines) {
          final match = pragma.firstMatch(line);
          if (match != null) {
            final initial = double.tryParse(match[3]!);
            final minimum = double.tryParse(match[4]!);
            final maximum = double.tryParse(match[5]!);
            final step = double.tryParse(match[6] ?? '');
            if (initial == null ||
                minimum == null ||
                maximum == null ||
                !initial.isFinite ||
                !minimum.isFinite ||
                !maximum.isFinite ||
                maximum <= minimum) {
              continue;
            }
            declarations[match[1]!] = RetroArchShaderParameter(
              id: match[1]!,
              name: match[2]!,
              minimum: minimum,
              maximum: maximum,
              initial: initial.clamp(minimum, maximum),
              step: step != null && step.isFinite && step > 0
                  ? step
                  : (maximum - minimum) / 100,
            );
          } else if (path.extension(canonical) == '.${format}p') {
            final match = setting.firstMatch(line);
            final value = double.tryParse(match?[2] ?? '');
            if (match != null && value != null && value.isFinite) {
              defaults[match[1]!] = value;
            }
          }
        }
      } on FileSystemException {
        return;
      } on FormatException {
        return;
      }
    }

    await visit(File(filename));
    return [
      for (final parameter in declarations.values)
        RetroArchShaderParameter(
          id: parameter.id,
          name: parameter.name,
          minimum: parameter.minimum,
          maximum: parameter.maximum,
          initial: (defaults[parameter.id] ?? parameter.initial).clamp(
            parameter.minimum,
            parameter.maximum,
          ),
          step: parameter.step,
        ),
    ];
  }

  Future<String?> withParameters(
    String id,
    Directory scratch,
    Map<String, double> values,
  ) async {
    final original = await resolve(id);
    if (original == null || original.contains(RegExp(r'["\r\n]'))) return null;
    final parameters = await this.parameters(id);
    final overrides = {
      for (final parameter in parameters)
        if (values[parameter.id] case final value? when value.isFinite)
          parameter.id: value.clamp(parameter.minimum, parameter.maximum),
    };
    if (overrides.isEmpty) return null;
    final preset = File(path.join(scratch.path, 'session.${format}p'));
    await preset.writeAsString(
      [
        '#reference "$original"',
        for (final entry in overrides.entries)
          '${entry.key} = "${entry.value}"',
        '',
      ].join('\n'),
    );
    return preset.path;
  }
}
