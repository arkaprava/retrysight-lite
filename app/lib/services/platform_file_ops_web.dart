import 'dart:html' as html;

Future<void> deleteSqliteDatabaseFiles(String dataDirPath) async {
  throw UnsupportedError('Database reset is not supported in the web UI');
}

/// Triggers a browser download of the CSV via a Blob URL — the standard way
/// to save a generated file client-side in Flutter web (no file-picker
/// dependency needed). Returns the suggested file name; the browser controls
/// where it actually lands.
Future<String> saveCsvExport(String csv, String suggestedFileName) async {
  final blob = html.Blob([csv], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', suggestedFileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return suggestedFileName;
}
