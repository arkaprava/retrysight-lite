// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Removes sensitive query parameters from the browser URL after they are consumed.
void stripSensitiveQueryParams() {
  final uri = Uri.base;
  if (!uri.queryParameters.containsKey('token') &&
      !uri.queryParameters.containsKey('port')) {
    return;
  }
  html.window.history.replaceState(
    null,
    '',
    uri.replace(queryParameters: <String, dynamic>{}).path,
  );
}
