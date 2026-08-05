import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/config_service.dart';
import 'utils/web_url.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    final configService = ConfigService();
    final existing = await configService.load();
    final token = Uri.base.queryParameters['token'];
    final portStr = Uri.base.queryParameters['port'];
    final port = portStr != null ? int.tryParse(portStr) : null;
    if ((token != null && token.isNotEmpty && existing.adminToken.isEmpty) ||
        (port != null && port != existing.port)) {
      await configService.save(
        existing.copyWith(
          adminToken: (token != null && token.isNotEmpty)
              ? token
              : existing.adminToken,
          port: port ?? existing.port,
        ),
      );
    }
    stripSensitiveQueryParams();
  }

  runApp(const ProviderScope(child: RetrySightLiteApp()));
}
