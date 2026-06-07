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
    elevation: 0,
    color: Colors.white.withOpacity(0.7),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.black.withOpacity(0.05)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    filled: true,
    fillColor: Colors.white.withOpacity(0.5),
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  ),
  dataTableTheme: const DataTableThemeData(
    headingTextStyle: TextStyle(fontWeight: FontWeight.w600),
  ),
  navigationRailTheme: NavigationRailThemeData(
    labelType: NavigationRailLabelType.none,
    groupAlignment: -0.85,
    backgroundColor: Colors.white.withOpacity(0.8),
    selectedIconTheme: const IconThemeData(size: 28, opacity: 1.0, color: Colors.indigo),
    unselectedIconTheme: const IconThemeData(size: 24, opacity: 0.6),
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 65,
    backgroundColor: Colors.white.withOpacity(0.8),
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
    elevation: 0,
    color: Colors.black.withOpacity(0.4),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    filled: true,
    fillColor: Colors.black.withOpacity(0.3),
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  ),
  dataTableTheme: const DataTableThemeData(
    headingTextStyle: TextStyle(fontWeight: FontWeight.w600),
  ),
  navigationRailTheme: NavigationRailThemeData(
    labelType: NavigationRailLabelType.none,
    groupAlignment: -0.85,
    backgroundColor: const Color(0xFF1C1B1F).withOpacity(0.8),
    selectedIconTheme: IconThemeData(size: 28, opacity: 1.0, color: Colors.indigo.shade200),
    unselectedIconTheme: const IconThemeData(size: 24, opacity: 0.6),
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 65,
    backgroundColor: const Color(0xFF1C1B1F).withOpacity(0.8),
    labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
  ),
  pageTransitionsTheme: _pageTransitions,
);