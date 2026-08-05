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
