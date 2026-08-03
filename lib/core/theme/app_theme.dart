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

  // Container tones.
  //
  // These are set explicitly rather than left to ColorScheme.fromSeed.
  // `fromSeed` builds a tonal palette by desaturating the seed hard, so a
  // vivid grass green arrives on screen as a pale grey-green and the red
  // never appears at all outside a FAB — the app ends up looking like
  // stock Material with a green tint. The roles below are the ones the UI
  // actually reads (see `grep colorScheme.` across lib/), so pinning them is
  // what makes the palette the product's own.
  static const Color greenContainer = Color(0xFFDCFCE7);   // Fresh turf tint
  static const Color onGreenContainer = Color(0xFF052E16); // Ink on turf
  static const Color redContainer = Color(0xFFFEE2E2);     // Ball red tint
  static const Color onRedContainer = Color(0xFF7F1D1D);   // Ink on ball red
  static const Color turfLine = Color(0xFFE3F5E9);         // Ground marking

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
          primaryContainer: greenContainer,
          onPrimaryContainer: onGreenContainer,
          secondary: accentBallRed,
          onSecondary: Colors.white,
          // The one role that decides whether anyone ever sees the red. Every
          // call-to-action card in the app is a `secondaryContainer` — "Open
          // entries", "Generate the draw", "Start the event".
          secondaryContainer: redContainer,
          onSecondaryContainer: onRedContainer,
          tertiary: vibrantEmerald,
          tertiaryContainer: greenContainer,
          onTertiaryContainer: onGreenContainer,
          surface: Colors.white,
          // The scoreboard's own background, so a live score sits on turf
          // rather than on Material's default grey.
          surfaceContainerHighest: turfLine,
          onSurfaceVariant: primaryTurfDark,
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
        // The navigation chrome is on screen on every single route, so it is
        // the largest single contributor to what colour the app "is". Left at
        // Material's defaults it renders a neutral grey bar under a green app
        // bar, which is what made the palette look like it had not been
        // applied at all.
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: greenContainer,
          surfaceTintColor: Colors.transparent,
          elevation: 3,
          shadowColor: primaryTurfGreen.withValues(alpha: 0.2),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? primaryTurfDark
                  : primaryTurfGreen.withValues(alpha: 0.65),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? primaryTurfDark
                  : primaryTurfGreen.withValues(alpha: 0.75),
            ),
          ),
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.white,
          indicatorColor: greenContainer,
          selectedIconTheme: const IconThemeData(color: primaryTurfDark),
          unselectedIconTheme: IconThemeData(
            color: primaryTurfGreen.withValues(alpha: 0.65),
          ),
          selectedLabelTextStyle: const TextStyle(
            color: primaryTurfDark,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: primaryTurfGreen.withValues(alpha: 0.75),
          ),
        ),
        tabBarTheme: const TabBarTheme(
          labelColor: primaryTurfDark,
          unselectedLabelColor: Color(0xFF6B7F70),
          indicatorColor: accentBallRed,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        // Red, not green. A spinner is the one place the accent should
        // interrupt: it is the app saying "wait", and it must not blend into
        // the turf behind it.
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: accentBallRed,
          circularTrackColor: turfLine,
        ),
        dividerTheme: const DividerThemeData(color: turfLine, thickness: 1),
        listTileTheme: const ListTileThemeData(iconColor: primaryTurfGreen),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFF8AA694),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? primaryTurfGreen
                : turfLine,
          ),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? primaryTurfGreen
                : const Color(0xFF8AA694),
          ),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? primaryTurfGreen
                : Colors.transparent,
          ),
          checkColor: const WidgetStatePropertyAll(Colors.white),
        ),
        inputDecorationTheme: _inputTheme,
      );

  /// Every form field on every screen declares `border: OutlineInputBorder()`
  /// inline, which is why the field borders were the last grey thing left.
  /// Set here so the green applies without touching thirty call sites.
  static final InputDecorationTheme _inputTheme = InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: primaryTurfGreen.withValues(alpha: 0.35)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primaryTurfGreen, width: 2),
    ),
    floatingLabelStyle: const TextStyle(color: primaryTurfDark),
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
