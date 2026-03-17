import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 長夜印信 - 紅客主題
///
/// 基礎配色由 Material 3 `ColorScheme.fromSeed(seedColor: Colors.red)` 自動生成。
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.red,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.0,
          fontFamily: 'monospace',
          decoration: TextDecoration.none,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: AppColors.glow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: colorScheme.onSurface, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3.0, decoration: TextDecoration.none),
        headlineMedium: TextStyle(color: colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 2.0, decoration: TextDecoration.none),
        titleLarge: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 1.0, decoration: TextDecoration.none),
        titleMedium: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w400, decoration: TextDecoration.none),
        bodyLarge: TextStyle(color: colorScheme.onSurface, fontSize: 16, decoration: TextDecoration.none),
        bodyMedium: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, decoration: TextDecoration.none),
        labelLarge: TextStyle(color: colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5, decoration: TextDecoration.none),
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 24),
      dividerTheme: DividerThemeData(color: colorScheme.outline.withValues(alpha: 0.4), thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, decoration: TextDecoration.none),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5), decoration: TextDecoration.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary, elevation: 4),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6), width: 1)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5, decoration: TextDecoration.none),
        ),
      ),
    );
  }
}
