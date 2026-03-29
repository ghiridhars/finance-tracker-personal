/// Theme definitions for Finance Tracker v2
/// Supports light and dark mode with Material 3 semantic colors.
/// Includes page transition animations for smooth navigation.
import 'package:flutter/material.dart';

/// Shared page transitions for smooth navigation.
const _pageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
  },
);

/// Light theme — default
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.light,
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    filled: true,
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  ),
  dataTableTheme: const DataTableThemeData(
    headingTextStyle: TextStyle(fontWeight: FontWeight.w600),
  ),
  navigationRailTheme: const NavigationRailThemeData(
    labelType: NavigationRailLabelType.none,
    groupAlignment: -0.85,
  ),
  navigationBarTheme: const NavigationBarThemeData(
    height: 65,
    labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
  ),
  pageTransitionsTheme: _pageTransitions,
);

/// Dark theme
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.dark,
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    filled: true,
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  ),
  dataTableTheme: const DataTableThemeData(
    headingTextStyle: TextStyle(fontWeight: FontWeight.w600),
  ),
  navigationRailTheme: const NavigationRailThemeData(
    labelType: NavigationRailLabelType.none,
    groupAlignment: -0.85,
  ),
  navigationBarTheme: const NavigationBarThemeData(
    height: 65,
    labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
  ),
  pageTransitionsTheme: _pageTransitions,
);