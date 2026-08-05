import 'package:flutter_test/flutter_test.dart';
import 'package:retrysight_lite/models/app_config.dart';
import 'package:retrysight_lite/utils/app_paths.dart';

void main() {
  group('AppPaths bundled backend candidates', () {
    test('macOS candidate is under app Resources', () {
      final paths = AppPaths.bundledBackendBinaryCandidates(
        executablePath: '/Applications/RetrySight Lite.app/Contents/MacOS/RetrySight Lite',
        isMacOS: true,
        isWindows: false,
        isLinux: false,
      ).toList();
      expect(
        paths,
        contains('/Applications/RetrySight Lite.app/Contents/Resources/retrysight-lite'),
      );
    });

    test('Windows candidates include exe dir and data dir', () {
      final paths = AppPaths.bundledBackendBinaryCandidates(
        executablePath: 'C:/Program Files/RetrySight Lite/retrysightlite.exe',
        isMacOS: false,
        isWindows: true,
        isLinux: false,
      ).toList();
      expect(
        paths,
        containsAll([
          'C:/Program Files/RetrySight Lite/retrysight-lite.exe',
          'C:/Program Files/RetrySight Lite/data/retrysight-lite.exe',
        ]),
      );
    });

    test('Linux candidate sits next to the Flutter executable', () {
      final paths = AppPaths.bundledBackendBinaryCandidates(
        executablePath: '/opt/retrysight/bundle/retrysightlite',
        isMacOS: false,
        isWindows: false,
        isLinux: true,
      ).toList();
      expect(paths, contains('/opt/retrysight/bundle/retrysight-lite'));
    });
  });

  group('AppPaths backend environment', () {
    test('includes headless flags and data dir', () {
      const config = AppConfig(
        dataDir: '/tmp/retrysight/data',
        port: 19090,
      );
      final env = AppPaths.backendEnvironment(config);
      expect(env['RETRYSIGHT_HEADLESS'], '1');
      expect(env['RETRYSIGHT_PORT'], '19090');
      expect(env['RETRYSIGHT_DATA_DIR'], '/tmp/retrysight/data');
      expect(env['RETRYSIGHT_DB_PATH'], '/tmp/retrysight/data/retrysight-lite.db');
    });
  });

  group('AppPaths admin token files', () {
    test('lists configured and installed data dirs', () {
      final paths = AppPaths.adminTokenFileCandidates(
        dataDir: '/tmp/app-data',
        managerPath: '/tmp/manager',
      ).toList();
      expect(
        paths,
        containsAll([
          '/tmp/app-data/admin-token',
          '/tmp/manager/data/admin-token',
        ]),
      );
    });
  });

  group('AppPaths working directory', () {
    test('prefers data dir parent', () {
      expect(
        AppPaths.backendWorkingDir(dataDir: '/tmp/retrysight/data'),
        '/tmp/retrysight',
      );
    });
  });
}
