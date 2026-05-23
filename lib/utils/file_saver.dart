/// 平台感知的檔案輸出工具
///
/// 根據執行平台自動選擇適當的檔案輸出方式：
/// - 桌面（Windows/macOS/Linux）：彈出儲存對話框
/// - 行動裝置（Android/iOS）：呼叫系統分享功能
/// - Web：觸發瀏覽器下載
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

// ============================================================
// 平台類型
// ============================================================

/// 檔案輸出的目標平台類型
enum OutputPlatform {
  /// 桌面：Windows、macOS、Linux — 使用儲存對話框
  desktop,

  /// 行動裝置：Android、iOS — 使用系統分享
  mobile,

  /// Web 瀏覽器 — 觸發下載
  web,
}

/// 取得目前執行平台的輸出類型
OutputPlatform get currentOutputPlatform {
  if (kIsWeb) return OutputPlatform.web;
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return OutputPlatform.mobile;
  }
  return OutputPlatform.desktop;
}

// ============================================================
// 圖示
// ============================================================

/// 取得平台對應的檔案輸出按鈕圖示
///
/// - 桌面：儲存圖示
/// - 行動裝置：分享圖示
/// - Web：下載圖示
IconData get outputFileIcon {
  switch (currentOutputPlatform) {
    case OutputPlatform.desktop:
      return Icons.save_outlined;
    case OutputPlatform.mobile:
      return Icons.share_outlined;
    case OutputPlatform.web:
      return Icons.download_outlined;
  }
}

/// 取得平台對應的「全部輸出」按鈕圖示
IconData get outputAllIcon {
  switch (currentOutputPlatform) {
    case OutputPlatform.desktop:
      return Icons.save_alt_outlined;
    case OutputPlatform.mobile:
      return Icons.share_outlined;
    case OutputPlatform.web:
      return Icons.download_outlined;
  }
}

// ============================================================
// 標籤選擇
// ============================================================

/// 根據平台選擇對應的按鈕文字
///
/// [desktop] 桌面版文字（如「儲存金鑰」）
/// [mobile] 行動版文字（如「匯出金鑰」）
/// [web] Web 版文字（如「下載金鑰」）
String platformFileLabel({
  required String desktop,
  required String mobile,
  required String web,
}) {
  switch (currentOutputPlatform) {
    case OutputPlatform.desktop:
      return desktop;
    case OutputPlatform.mobile:
      return mobile;
    case OutputPlatform.web:
      return web;
  }
}

// ============================================================
// 檔案輸出（含使用者回饋）
// ============================================================

/// 統一的檔案輸出方法，自動根據平台選擇操作方式並顯示 SnackBar 回饋
///
/// - 桌面：彈出原生儲存對話框
/// - 行動裝置：透過系統分享功能匯出檔案
/// - Web：觸發瀏覽器下載
///
/// [context] BuildContext，用於顯示 SnackBar
/// [l10n] 本地化物件
/// [content] 要輸出的文字內容（PEM 等）
/// [defaultFileName] 預設檔案名稱
/// [dialogTitle] 儲存對話框標題（僅桌面使用）
/// [debugTag] DEBUG 輸出標籤（如 `[CreateKeyScreen]`）
Future<void> outputFileWithFeedback({
  required BuildContext context,
  required AppLocalizations l10n,
  required String content,
  required String defaultFileName,
  String? dialogTitle,
  String debugTag = '[FileSaver]',
}) async {
  debugPrint('$debugTag 輸出檔案: $defaultFileName (平台: ${currentOutputPlatform.name})');

  final Uint8List bytes = Uint8List.fromList(utf8.encode(content));

  try {
    switch (currentOutputPlatform) {
      // ── 桌面：儲存對話框 ──
      case OutputPlatform.desktop:
        final String? outputPath = await FilePicker.saveFile(
          dialogTitle: dialogTitle ?? l10n.dialogSaveFile,
          fileName: defaultFileName,
          type: FileType.any,
          bytes: bytes,
        );

        if (outputPath != null && outputPath.isNotEmpty) {
          debugPrint('$debugTag 檔案已儲存至: $outputPath');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.savedToPath(outputPath)),
                duration: const Duration(seconds: 2),
                backgroundColor: AppColors.surface,
              ),
            );
          }
        }

      // ── 行動裝置：系統分享 ──
      case OutputPlatform.mobile:
        final XFile xFile = XFile.fromData(
          bytes,
          name: defaultFileName,
          mimeType: 'application/octet-stream',
        );
        final ShareResult result = await Share.shareXFiles([xFile]);

        if (result.status == ShareResultStatus.success) {
          debugPrint('$debugTag 檔案已分享: $defaultFileName');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.fileSharedSuccess),
                duration: const Duration(seconds: 2),
                backgroundColor: AppColors.surface,
              ),
            );
          }
        } else {
          debugPrint('$debugTag 分享已取消或失敗: ${result.status}');
        }

      // ── Web：瀏覽器下載 ──
      case OutputPlatform.web:
        await FilePicker.saveFile(
          dialogTitle: dialogTitle ?? l10n.dialogSaveFile,
          fileName: defaultFileName,
          type: FileType.any,
          bytes: bytes,
        );

        debugPrint('$debugTag 已觸發下載: $defaultFileName');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.fileDownloaded(defaultFileName)),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.surface,
            ),
          );
        }
    }
  } catch (e) {
    debugPrint('$debugTag 輸出失敗: $e');
    if (context.mounted) {
      final String errorMsg = switch (currentOutputPlatform) {
        OutputPlatform.desktop => l10n.saveFailed(e.toString()),
        OutputPlatform.mobile => l10n.shareFailed(e.toString()),
        OutputPlatform.web => l10n.downloadFailed(e.toString()),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
