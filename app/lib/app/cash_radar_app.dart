import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class CashRadarRouterApp extends ConsumerWidget {
  const CashRadarRouterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'CashRadar',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff087f77),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff7f9f8),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe3eae7)),
        ),
      ),
    ),
    routerConfig: ref.watch(routerProvider),
  );
}
