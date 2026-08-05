import 'package:path/path.dart' as p;

/// Validates that [rawPath] resolves to an absolute path without traversal escapes.
String resolveSafeDataDir(String rawPath) {
  if (rawPath.trim().isEmpty) {
    throw ArgumentError('Data directory path is empty');
  }
  final trimmed = rawPath.trim();
  if (trimmed.contains('..')) {
    throw ArgumentError('Invalid data directory path: $rawPath');
  }
  return p.normalize(p.absolute(trimmed));
}

/// Returns true when [filePath] is inside [rootDir] (both must be absolute).
bool isPathInsideRoot(String filePath, String rootDir) {
  final file = p.normalize(p.absolute(filePath));
  final root = p.normalize(p.absolute(rootDir));
  if (file == root) return true;
  return file.startsWith('$root${p.separator}');
}
