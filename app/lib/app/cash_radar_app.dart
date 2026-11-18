import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'app_theme.dart';
import 'theme_preference.dart';

class CashRadarRouterApp extends ConsumerWidget {
  const CashRadarRouterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'CashRadar',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    darkTheme: buildAppTheme(Brightness.dark),
    themeMode: ref.watch(appDarkModeProvider)
        ? ThemeMode.dark
        : ThemeMode.light,
    routerConfig: ref.watch(routerProvider),
  );
}
