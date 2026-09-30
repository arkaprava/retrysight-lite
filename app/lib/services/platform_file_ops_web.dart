import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> deleteSqliteDatabaseFiles(String dataDirPath) async {
  throw UnsupportedError('Database reset is not supported in the web UI');
}

/// Triggers a browser download of the CSV via a Blob URL — the standard way
/// to save a generated file client-side in Flutter web (no file-picker
/// dependency needed). Returns the suggested file name; the browser controls
/// where it actually lands.
Future<String> saveCsvExport(String csv, String suggestedFileName) async {
  final blob = web.Blob(
    [csv.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = suggestedFileName
    ..click();
  web.URL.revokeObjectURL(url);
  return suggestedFileName;
}
