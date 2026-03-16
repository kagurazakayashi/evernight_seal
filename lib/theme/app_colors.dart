import 'package:flutter/material.dart';

/// 長夜印信 - 紅調马卡龙色系
///
/// 基礎配色由 Material 3 `ColorScheme.fromSeed` 自動生成。
/// 自訂色彩採用马卡龙低飽和、柔和粉彩風格。
class AppColors {
  AppColors._();

  // ── 基底 ──
  static const Color background = Color(0xFF1C1414); // 奶油可可底

  // ── 自訂主色（马卡龙紅調） ──
  static const Color surface = Color(0xFF261A1A); // 淺可可表面
  static const Color surfaceLight = Color(0xFF322222); // 亮可可表面
  static const Color primary = Color(0xFFC47A7A); // 豆沙紅
  static const Color primaryLight = Color(0xFFD4A0A0); // 淺豆沙紅
  static const Color primaryDark = Color(0xFF8B5A5A); // 深豆沙紅
  static const Color accent = Color(0xFFE8A0A0); // 玫瑰馬卡龍

  // ── 輝光 ──
  static const Color glow = Color(0x33E8A0A0); // 柔和玫瑰輝光
  static const Color glowStrong = Color(0x55D4A0A0); // 強柔輝光

  // ── 文字 ──
  static const Color textPrimary = Color(0xFFF0E8E8); // 暖白
  static const Color textSecondary = Color(0xFFC8B0B0); // 暖灰粉
  static const Color textHint = Color(0xFF8A7070); // 灰粉提示

  // ── 狀態 ──
  static const Color success = Color(0xFF8CC090); // 薄荷綠
  static const Color warning = Color(0xFFE0C080); // 奶油琥珀
  static const Color error = Color(0xFFD09090); // 柔和錯誤紅

  // ── 背景漸層 ──
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF221818), Color(0xFF160E0E)],
  );

  // ── 裝飾漸層 ──
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );
}
