import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF2F6BFF);
  static ThemeData light() => _build(Brightness.light, false);
  static ThemeData dark({bool amoled = true}) =>
      _build(Brightness.dark, amoled);

  static ThemeData _build(Brightness b, bool amoled) {
    final dark = b == Brightness.dark;
    var cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    if (dark && amoled) {
      cs = cs.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF090909),
        surfaceContainer: const Color(0xFF0F0F0F),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
      );
    }
    final bg = dark
        ? (amoled ? Colors.black : const Color(0xFF0A0F1E))
        : const Color(0xFFF2F5FC);
    final card = dark
        ? (amoled ? const Color(0xFF0E0E0E) : const Color(0xFF121A2E))
        : Colors.white;
    final field = dark
        ? (amoled ? const Color(0xFF181818) : const Color(0xFF19233B))
        : const Color(0xFFE5EAF7);
    RoundedRectangleBorder round(double r) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: round(16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: round(16),
          side: BorderSide(color: cs.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: round(14)),
      ),
      listTileTheme: ListTileThemeData(shape: round(18)),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: round(14),
      ),
      dialogTheme: DialogThemeData(shape: round(24)),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
    );
  }
}
