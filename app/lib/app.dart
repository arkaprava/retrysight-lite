import 'package:flutter/material.dart';

import 'constants/app_info.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class RetrySightLiteApp extends StatelessWidget {
  const RetrySightLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
