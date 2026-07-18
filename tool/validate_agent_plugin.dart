// Validates the repo-distributed agent plugin (Claude Code + OpenAI Codex)
// against the invariants that keep it installable and in sync with the
// package release:
//
//   dart tool/validate_agent_plugin.dart
//
// Checks: manifest JSON validity and required fields, kebab-case names,
// version sync with pubspec.yaml, marketplace source paths, skill frontmatter,
// resolvable relative links, no absolute/escaping paths, no secret-looking
// strings, and pub-archive exclusion of the plugin tree. Exits non-zero with
// one line per failure. Uses only dart: libraries so it runs pre-`pub get`.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const pluginRoot = 'agent-plugin/cached-video-thumbnail';
const claudeManifestPath = '$pluginRoot/.claude-plugin/plugin.json';
const codexManifestPath = '$pluginRoot/.codex-plugin/plugin.json';
const claudeMarketplacePath = '.claude-plugin/marketplace.json';
const codexMarketplacePath = '.agents/plugins/marketplace.json';

final _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _errors = <String>[];

void fail(String message) => _errors.add(message);

void main() {
  final pubspecVersion = _readPubspecVersion();

  final claude = _readJson(claudeManifestPath);
  final codex = _readJson(codexManifestPath);
  final claudeMarket = _readJson(claudeMarketplacePath);
  final codexMarket = _readJson(codexMarketplacePath);

  if (claude != null) {
    _checkManifest(claudeManifestPath, claude, pubspecVersion);
  }
  if (codex != null) {
    _checkManifest(codexManifestPath, codex, pubspecVersion);
    if (codex['skills'] is String &&
        !Directory('$pluginRoot/skills').existsSync()) {
      fail('$codexManifestPath: declares skills dir but none exists');
    }
  }
  if (claude != null && codex != null && claude['name'] != codex['name']) {
    fail(
      'plugin manifests disagree on name: '
      '${claude['name']} vs ${codex['name']}',
    );
  }

  if (claudeMarket != null) {
    _checkClaudeMarketplace(claudeMarket, claude);
  }
  if (codexMarket != null) {
    _checkCodexMarketplace(codexMarket, codex);
  }

  _checkSkills();
  _checkAgents();
  _checkTreeHygiene();
  _checkPubExclusion();

  if (_errors.isEmpty) {
    print(
      'agent plugin OK: manifests, marketplaces, skills, and version '
      '$pubspecVersion are consistent.',
    );
    return;
  }
  for (final error in _errors) {
    print('FAIL: $error');
  }
  exitCode = 1;
}

String _readPubspecVersion() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  for (final line in lines) {
    final match = RegExp(r'^version:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  fail('pubspec.yaml: no version field found');
  return '<missing>';
}

Map<String, Object?>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path: missing');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
    fail('$path: top-level JSON value must be an object');
  } on FormatException catch (e) {
    fail('$path: invalid JSON (${e.message})');
  }
  return null;
}

void _checkManifest(
  String path,
  Map<String, Object?> manifest,
  String pubspecVersion,
) {
  final name = manifest['name'];
  if (name is! String || !_kebabCase.hasMatch(name)) {
    fail('$path: "name" must be kebab-case, got: $name');
  }
  final version = manifest['version'];
  if (version != pubspecVersion) {
    fail('$path: version $version != pubspec version $pubspecVersion');
  }
  final description = manifest['description'];
  if (description is! String || description.isEmpty) {
    fail('$path: "description" is required');
  }
}

void _checkClaudeMarketplace(
  Map<String, Object?> market,
  Map<String, Object?>? plugin,
) {
  const path = claudeMarketplacePath;
  final name = market['name'];
  if (name is! String || !_kebabCase.hasMatch(name)) {
    fail('$path: marketplace "name" must be kebab-case, got: $name');
  }
  if (market['owner'] is! Map || (market['owner']! as Map)['name'] is! String) {
    fail('$path: "owner.name" is required');
  }
  final plugins = market['plugins'];
  if (plugins is! List || plugins.isEmpty) {
    fail('$path: "plugins" must be a non-empty array');
    return;
  }
  final names = <Object?>{};
  for (final entry in plugins.whereType<Map<String, Object?>>()) {
    if (!names.add(entry['name'])) {
      fail('$path: duplicate plugin name ${entry['name']}');
    }
    final source = entry['source'];
    if (source is! String || !source.startsWith('./')) {
      fail('$path: plugin source must be a ./relative path, got: $source');
    } else if (source.contains('..')) {
      fail('$path: plugin source must not traverse upwards: $source');
    } else if (!Directory(source.substring(2)).existsSync()) {
      fail('$path: plugin source does not exist: $source');
    }
    if (plugin != null &&
        entry['name'] == plugin['name'] &&
        entry.containsKey('version') &&
        entry['version'] != plugin['version']) {
      fail(
        '$path: entry version ${entry['version']} != plugin.json '
        '${plugin['version']}',
      );
    }
  }
  if (plugin != null && !names.contains(plugin['name'])) {
    fail('$path: no entry for plugin ${plugin['name']}');
  }
}

void _checkCodexMarketplace(
  Map<String, Object?> market,
  Map<String, Object?>? plugin,
) {
  const path = codexMarketplacePath;
  final name = market['name'];
  if (name is! String || !_kebabCase.hasMatch(name)) {
    fail('$path: marketplace "name" must be kebab-case, got: $name');
  }
  final plugins = market['plugins'];
  if (plugins is! List || plugins.isEmpty) {
    fail('$path: "plugins" must be a non-empty array');
    return;
  }
  var found = false;
  for (final entry in plugins.whereType<Map<String, Object?>>()) {
    if (plugin != null && entry['name'] == plugin['name']) found = true;
    if (entry['category'] is! String) {
      fail('$path: entry ${entry['name']} needs a "category"');
    }
    final source = entry['source'];
    if (source is! Map<String, Object?> || source['source'] != 'local') {
      fail(
        '$path: entry ${entry['name']} source must be '
        '{"source": "local", "path": ...}',
      );
      continue;
    }
    final sourcePath = source['path'];
    if (sourcePath is! String ||
        !sourcePath.startsWith('./') ||
        sourcePath.contains('..')) {
      fail(
        '$path: entry source path must be ./relative without "..": '
        '$sourcePath',
      );
    } else if (!Directory(sourcePath.substring(2)).existsSync()) {
      fail('$path: entry source path does not exist: $sourcePath');
    }
  }
  if (plugin != null && !found) {
    fail('$path: no entry for plugin ${plugin['name']}');
  }
}

void _checkSkills() {
  final skillsDir = Directory('$pluginRoot/skills');
  if (!skillsDir.existsSync()) {
    fail('$pluginRoot/skills: missing');
    return;
  }
  final skillDirs = skillsDir.listSync().whereType<Directory>().toList();
  if (skillDirs.isEmpty) {
    fail('$pluginRoot/skills: no skills found');
  }
  for (final dir in skillDirs) {
    final dirName = dir.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
    );
    final skillFile = File('${dir.path}/SKILL.md');
    if (!_kebabCase.hasMatch(dirName)) {
      fail('${dir.path}: skill directory must be kebab-case');
    }
    if (!skillFile.existsSync()) {
      fail('${dir.path}: missing SKILL.md');
      continue;
    }
    final frontmatter = _parseFrontmatter(skillFile);
    if (frontmatter == null) continue;
    final name = frontmatter['name'];
    if (name != dirName) {
      fail(
        '${skillFile.path}: frontmatter name "$name" != directory '
        '"$dirName"',
      );
    }
    final description = frontmatter['description'] ?? '';
    if (description.isEmpty) {
      fail('${skillFile.path}: frontmatter "description" is required');
    } else if (description.length > 1024) {
      fail('${skillFile.path}: description exceeds 1024 characters');
    }
  }
}

void _checkAgents() {
  final agentsDir = Directory('$pluginRoot/agents');
  if (!agentsDir.existsSync()) return;
  final files = agentsDir.listSync().whereType<File>().where(
    (file) => file.path.endsWith('.md'),
  );
  for (final file in files) {
    final frontmatter = _parseFrontmatter(file);
    if (frontmatter == null) continue;
    for (final key in ['name', 'description']) {
      if ((frontmatter[key] ?? '').isEmpty) {
        fail('${file.path}: agent frontmatter "$key" is required');
      }
    }
  }
}

/// Parses simple single-line `key: value` YAML frontmatter, which is the only
/// shape used in this plugin. Reports and returns null when absent.
Map<String, String>? _parseFrontmatter(File file) {
  final lines = file.readAsLinesSync();
  if (lines.isEmpty || lines.first.trim() != '---') {
    fail('${file.path}: missing YAML frontmatter');
    return null;
  }
  final end = lines.indexWhere((line) => line.trim() == '---', 1);
  if (end == -1) {
    fail('${file.path}: unterminated YAML frontmatter');
    return null;
  }
  final result = <String, String>{};
  for (final line in lines.sublist(1, end)) {
    if (line.trim().isEmpty) continue;
    final separator = line.indexOf(':');
    if (separator == -1) {
      fail('${file.path}: malformed frontmatter line: $line');
      continue;
    }
    result[line.substring(0, separator).trim()] = line
        .substring(separator + 1)
        .trim();
  }
  return result;
}

void _checkTreeHygiene() {
  final root = Directory(pluginRoot);
  if (!root.existsSync()) {
    fail('$pluginRoot: missing');
    return;
  }
  final markdownLink = RegExp(r'\]\(([^)#\s]+)\)');
  final absolutePath = RegExp(r'(/Users/|/home/|[A-Z]:\\)');
  final secretLike = RegExp(
    '(sk-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}'
    '|-----BEGIN [A-Z ]*PRIVATE KEY)',
  );
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    if (!path.endsWith('.md') &&
        !path.endsWith('.json') &&
        !path.endsWith('.dart')) {
      continue;
    }
    final content = entity.readAsStringSync();
    if (absolutePath.hasMatch(content)) {
      fail('$path: contains an absolute local path');
    }
    if (secretLike.hasMatch(content)) {
      fail('$path: contains a secret-looking string');
    }
    if (!path.endsWith('.md')) continue;
    for (final match in markdownLink.allMatches(content)) {
      final target = match.group(1)!;
      if (target.contains('://') || target.startsWith('mailto:')) continue;
      final resolved = File('${entity.parent.path}/$target');
      final resolvedDir = Directory('${entity.parent.path}/$target');
      if (!resolved.existsSync() && !resolvedDir.existsSync()) {
        fail('$path: broken relative link: $target');
      }
      final canonical = resolved.absolute.uri.normalizePath().toFilePath();
      if (!canonical.contains('agent-plugin')) {
        fail('$path: link escapes the plugin tree: $target');
      }
    }
  }
}

void _checkPubExclusion() {
  final pubignore = File('.pubignore');
  if (!pubignore.existsSync()) {
    fail('.pubignore: missing (plugin tree would ship to pub.dev)');
    return;
  }
  final lines = pubignore.readAsLinesSync().map((line) => line.trim()).toSet();
  if (!lines.contains('agent-plugin/')) {
    fail(
      '.pubignore: must exclude agent-plugin/ so the pub archive never '
      'ships a partial plugin',
    );
  }
}
