// Checks Sinew-to-Sinew package dependencies against tool/sinew_graph.txt.
// Fails on any edge not in the allow-list, and on sinew_testing outside dev_dependencies.
// Usage (from dart-lib/): dart run tool/check_graph.dart
import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  final allowed = File('tool/sinew_graph.txt')
      .readAsLinesSync()
      .map((l) => l.split('#').first.trim())
      .where((l) => l.isNotEmpty)
      .map((l) => l.split('->').map((s) => s.trim()).join(' -> '))
      .toSet();

  final problems = <String>[];
  final packages = Directory('packages').listSync().whereType<Directory>();
  for (final dir in packages) {
    final pubspec = loadYaml(File('${dir.path}/pubspec.yaml').readAsStringSync()) as YamlMap;
    final name = pubspec['name'] as String;
    final deps = (pubspec['dependencies'] as YamlMap?)?.keys.cast<String>() ?? const <String>[];
    for (final dep in deps.where((d) => d.startsWith('sinew_'))) {
      if (dep == 'sinew_testing') problems.add('$name lists sinew_testing outside dev_dependencies');
      if (!allowed.contains('$name -> $dep')) problems.add('$name -> $dep is not in tool/sinew_graph.txt');
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('Dependency graph check failed:');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
    exit(1);
  }
  stdout.writeln('Dependency graph OK (${allowed.length} allowed edges).');
}
