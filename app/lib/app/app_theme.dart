import 'package:flutter/material.dart';

abstract final class AppColors {
  static const yellow = Color(0xffffd500);
  static const ink = Color(0xff191919);
  static const lightBackground = Color(0xfff2f2ee);
  static const darkBackground = Color(0xff161616);
  static const darkSurface = Color(0xff202020);
  static const darkInset = Color(0xff2b2b2b);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final foreground = dark ? const Color(0xfff5f5f1) : const Color(0xff20201e);
  final surface = dark ? AppColors.darkSurface : Colors.white;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.yellow,
        brightness: brightness,
      ).copyWith(
        primary: dark ? AppColors.yellow : const Color(0xff222222),
        onPrimary: dark ? AppColors.ink : Colors.white,
        primaryContainer: AppColors.yellow,
        onPrimaryContainer: AppColors.ink,
        secondaryContainer: AppColors.yellow,
        onSecondaryContainer: AppColors.ink,
        surface: surface,
        onSurface: foreground,
        surfaceContainerLowest: dark ? AppColors.darkBackground : Colors.white,
        surfaceContainerLow: dark
            ? AppColors.darkInset
            : const Color(0xfff5f5f2),
        surfaceContainer: dark ? AppColors.darkSurface : Colors.white,
        surfaceContainerHigh: dark
            ? AppColors.darkInset
            : const Color(0xfff5f5f2),
        surfaceContainerHighest: dark
            ? const Color(0xff353535)
            : const Color(0xffeaeae5),
        outline: dark ? const Color(0xff777777) : const Color(0xffb8b8b0),
        outlineVariant: dark
            ? const Color(0xff454545)
            : const Color(0xffe4e4df),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final text = base.textTheme.apply(
    bodyColor: foreground,
    displayColor: foreground,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    hoverColor: foreground.withValues(alpha: dark ? .08 : .06),
    scaffoldBackgroundColor: dark
        ? AppColors.darkBackground
        : AppColors.lightBackground,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(
        color: dark ? const Color(0xffb8b8b0) : const Color(0xff777770),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: scheme.outlineVariant),
        shape: shape,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        shape: WidgetStatePropertyAll(shape),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.yellow,
      linearTrackColor: dark
          ? const Color(0xff3a3a3a)
          : const Color(0xffeaeae5),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.yellow,
      selectedIconTheme: const IconThemeData(color: AppColors.ink),
      selectedLabelTextStyle: TextStyle(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.yellow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.ink
              : foreground,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
  );
}
