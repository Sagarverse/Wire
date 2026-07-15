import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static const _themeModePrefKey = 'theme_mode';
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.system,
  );

  static ThemeMode get currentThemeMode => themeModeNotifier.value;

  static Future<void> initThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModePrefKey);
    switch (saved) {
      case 'light':
        themeModeNotifier.value = ThemeMode.light;
        break;
      case 'dark':
        themeModeNotifier.value = ThemeMode.dark;
        break;
      default:
        themeModeNotifier.value = ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    final encoded = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeModePrefKey, encoded);
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0891B2),       // Vibrant Teal-Cyan
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE0F7FA),
      onPrimaryContainer: Color(0xFF0C4A6E),
      secondary: Color(0xFF7C3AED),     // Rich Violet accent
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF3E8FF),
      onSecondaryContainer: Color(0xFF4C1D95),
      error: Color(0xFFEF4444),
      onError: Colors.white,
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F172A),
      outline: Color(0xFFE2E8F0),
      outlineVariant: Color(0xFFF1F5F9),
      tertiary: Color(0xFFF59E0B),       // Warm amber for highlights
      onTertiary: Colors.white,
      surfaceContainerHighest: Color(0xFFF1F5F9),
    );

    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF8FAFB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF22D3EE),       // Bright Cyan
      onPrimary: Color(0xFF0C4A6E),
      primaryContainer: Color(0xFF0E4D64),
      onPrimaryContainer: Color(0xFFE0F7FA),
      secondary: Color(0xFFA78BFA),     // Light Violet
      onSecondary: Color(0xFF1E1B4B),
      secondaryContainer: Color(0xFF1E1B4B),
      onSecondaryContainer: Color(0xFFEDE9FE),
      error: Color(0xFFFCA5A5),
      onError: Color(0xFF000000),
      surface: Color(0xFF0A0F1A),        // Deep navy instead of pure black
      onSurface: Color(0xFFE8ECF4),
      outline: Color(0xFF1A2332),
      outlineVariant: Color(0xFF111827),
      tertiary: Color(0xFFFBBF24),       // Warm gold
      onTertiary: Color(0xFF000000),
      surfaceContainerHighest: Color(0xFF111827),
    );

    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0A0F1A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData _baseTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final baseText = GoogleFonts.plusJakartaSansTextTheme(
      Typography.material2021().white.apply(
        displayColor: scheme.onSurface,
        bodyColor: scheme.onSurface,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      textTheme: baseText.copyWith(
        headlineLarge: baseText.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          height: 1.5,
          letterSpacing: 0.1,
        ),
        labelSmall: baseText.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
          textBaseline: TextBaseline.alphabetic,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
        backgroundColor:
            isDark ? const Color(0xFF1E2D45) : const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF111A2A).withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.95),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.32)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.32)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.78),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        backgroundColor: isDark
            ? const Color(0xFF111827).withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.9),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outline.withValues(alpha: 0.25),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline.withValues(alpha: 0.4),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 8,
        backgroundColor: isDark ? const Color(0xFF141C2E) : Colors.white,
      ),
    );
  }

  /// Standard animation durations for consistency
  static const Duration animationShort = Duration(milliseconds: 200);
  static const Duration animationStandard = Duration(milliseconds: 350);
  static const Duration animationLong = Duration(milliseconds: 500);

  /// Standard animation curves
  static const Curve curveEaseOut = Curves.easeOut;
  static const Curve curveEaseInOutCubic = Curves.easeInOutCubic;
  static const Curve curveEaseOutBack = Curves.easeOutBack;

  /// Shimmer color for loading states
  static Color shimmerColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
  }
}

extension ThemeFx on BuildContext {
  Color get fxTextPrimary => Theme.of(this).colorScheme.onSurface;
  Color get fxTextSecondary =>
      Theme.of(this).colorScheme.onSurface.withValues(
        alpha: Theme.of(this).brightness == Brightness.dark ? 0.72 : 0.62,
      );

  List<Color> get fxBackgroundGradient {
    final dark = Theme.of(this).brightness == Brightness.dark;
    return dark
        ? const [
            Color(0xFF000000), 
            Color(0xFF0A0A0A), 
            Color(0xFF121212), 
            Color(0xFF1A1A1A), 
          ]
        : const [
            Color(0xFFFFFFFF), 
            Color(0xFFF8FAFC), 
            Color(0xFFF1F5F9), 
            Color(0xFFE2E8F0), 
          ];
  }
}
