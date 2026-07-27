import 'package:flutter/material.dart';

/// Production-Grade Sports Operating System Design System & Aesthetics.
/// Tailored for multi-sport organizations, ground tournaments, and stadium events.
class AppTheme {
  AppTheme._();

  // Sports Ground Palette (Turf Grass & Sports Crimson Red)
  static const Color primaryTurfGreen = Color(0xFF16A34A); // Vibrant Grass Green
  static const Color primaryTurfDark = Color(0xFF15803D);  // Deep Stadium Green
  static const Color accentBallRed = Color(0xFFDC2626);    // Sports Crimson Red
  static const Color accentBallRedLight = Color(0xFFEF4444);
  static const Color vibrantEmerald = Color(0xFF10B981);
  static const Color amberGold = Color(0xFFF59E0B);

  // Surface & Stadium Colors
  static const Color darkBackground = Color(0xFF07140B); // Stadium Night Grass
  static const Color darkSurface = Color(0xFF0F2314);    // Stadium Card Surface
  static const Color darkSurfaceElevated = Color(0xFF18331E);
  static const Color lightBackground = Color(0xFFF0FDF4); // Soft Turf Light Green

  static LinearGradient get brandGradient => const LinearGradient(
        colors: [primaryTurfGreen, primaryTurfDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get ballRedGradient => const LinearGradient(
        colors: [accentBallRedLight, accentBallRed],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get stadiumNightGradient => const LinearGradient(
        colors: [darkBackground, darkSurface],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        primaryColor: primaryTurfGreen,
        scaffoldBackgroundColor: lightBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryTurfGreen,
          brightness: Brightness.light,
          primary: primaryTurfGreen,
          onPrimary: Colors.white,
          secondary: accentBallRed,
          onSecondary: Colors.white,
          tertiary: vibrantEmerald,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: primaryTurfDark,
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 3,
          shadowColor: primaryTurfGreen.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: primaryTurfGreen.withValues(alpha: 0.3), width: 1.2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryTurfGreen,
            foregroundColor: Colors.white,
            elevation: 3,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryTurfGreen,
            side: const BorderSide(color: primaryTurfGreen, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accentBallRed,
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: primaryTurfGreen.withValues(alpha: 0.1),
          side: BorderSide(color: primaryTurfGreen.withValues(alpha: 0.3)),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: primaryTurfDark),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        primaryColor: primaryTurfGreen,
        scaffoldBackgroundColor: darkBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryTurfGreen,
          brightness: Brightness.dark,
          surface: darkSurface,
          primary: primaryTurfGreen,
          onPrimary: Colors.white,
          secondary: accentBallRed,
          onSecondary: Colors.white,
          tertiary: vibrantEmerald,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: darkSurface,
          foregroundColor: Colors.white,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardTheme(
          color: darkSurface,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: primaryTurfGreen.withValues(alpha: 0.35), width: 1.2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryTurfGreen,
            foregroundColor: Colors.white,
            elevation: 4,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: primaryTurfGreen.withValues(alpha: 0.6), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accentBallRed,
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: darkSurfaceElevated,
          side: BorderSide(color: primaryTurfGreen.withValues(alpha: 0.4)),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
}
