import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static const _font = 'SF Pro Text';
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
      primary: Color(0xFF0061FF), // Classic Wire Blue
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE0E7FF),
      onPrimaryContainer: Color(0xFF001D6E),
      secondary: Color(0xFF475569), 
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF1F5F9),
      onSecondaryContainer: Color(0xFF1E293B),
      error: Color(0xFFDC2626), 
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF0F172A),
      outline: Color(0xFFE2E8F0),
      outlineVariant: Color(0xFFCBD5E1),
      tertiary: Color(0xFF3B82F6),
      onTertiary: Colors.white,
    );

    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
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
      primary: Color(0xFF60A5FA), // Light Blue for dark mode
      onPrimary: Color(0xFF0F172A),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF94A3B8),
      onSecondary: Color(0xFF0F172A),
      secondaryContainer: Color(0xFF1E293B),
      onSecondaryContainer: Color(0xFFF1F5F9),
      error: Color(0xFFF87171),
      onError: Color(0xFF7F1D1D),
      surface: Color(0xFF0F172A), // Deep Slate
      onSurface: Color(0xFFF1F5F9),
      outline: Color(0xFF334155),
      outlineVariant: Color(0xFF475569),
      tertiary: Color(0xFF38BDF8),
      onTertiary: Color(0xFF0C4A6E),
    );

    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF020617), // Near black blue
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData _baseTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final baseText = Typography.material2021().white.apply(
      displayColor: scheme.onSurface,
      bodyColor: scheme.onSurface,
      fontFamily: _font,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _font,
      textTheme: baseText.copyWith(
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.35),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF111927) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              ? scheme.primary
              : scheme.outline,
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
}

extension ThemeFx on BuildContext {
  Color get fxTextPrimary => Theme.of(this).colorScheme.onSurface;
  Color get fxTextSecondary => Theme.of(this).colorScheme.onSurface.withValues(
    alpha: Theme.of(this).brightness == Brightness.dark ? 0.72 : 0.62,
  );

  List<Color> get fxBackgroundGradient {
    final dark = Theme.of(this).brightness == Brightness.dark;
    return dark
        ? const [
            Color(0xFF020617), // Deep slate black
            Color(0xFF0F172A), // Midnight blue
            Color(0xFF1E293B), // Deep Slate
          ]
        : const [
            Color(0xFFF8FAFC), // Off-white
            Color(0xFFF1F5F9), // Light slate
            Color(0xFFEFF6FF), // Soft blue
          ];
  }
}
