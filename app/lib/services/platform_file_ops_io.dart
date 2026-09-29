import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/path_utils.dart';

Future<void> deleteSqliteDatabaseFiles(String dataDirPath) async {
  final dataDir = resolveSafeDataDir(dataDirPath);
  for (final name in [
    'retrysight-lite.db',
    'retrysight-lite.db-shm',
    'retrysight-lite.db-wal',
  ]) {
    final file = File(p.join(dataDir, name));
    if (!await file.exists()) continue;
    final resolved = p.normalize(p.absolute(await file.resolveSymbolicLinks()));
    if (!isPathInsideRoot(resolved, dataDir)) {
      throw StateError('File outside data directory: $resolved');
    }
    await file.delete();
  }
}

/// Writes exported CSV text to the user's Downloads folder (falling back to
/// their home directory if Downloads doesn't exist), returning the saved
/// path. No file-picker dependency — this is the same "just land it in
/// Downloads" behavior most desktop export features use.
Future<String> saveCsvExport(String csv, String suggestedFileName) async {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    throw StateError('Could not determine a home directory to save into');
  }
  final downloads = Directory(p.join(home, 'Downloads'));
  final targetDir = await downloads.exists() ? downloads.path : home;
  final file = File(p.join(targetDir, suggestedFileName));
  await file.writeAsString(csv);
  return file.path;
}
