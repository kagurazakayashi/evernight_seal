import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../utils/file_saver.dart';

/// 匯出憑證與私鑰畫面
///
/// 集中顯示所有已產生的項目（私鑰、CA 憑證、CSR、已簽發憑證、合併憑證鏈），
/// 提供一鍵儲存或複製功能。
class ExportScreen extends StatelessWidget {
  /// 從建立私鑰畫面產生的私鑰 PEM
  final String? lastGeneratedKeyPem;

  /// 從自簽名 CA 畫面產生的 CA 憑證 PEM
  final String? lastGeneratedCACertPem;

  /// 從建立 CSR 畫面產生的 CSR PEM
  final String? lastGeneratedCSRPem;

  /// 從簽發憑證畫面產生的已簽發憑證 PEM
  final String? lastIssuedCertPem;

  /// 從合併憑證畫面產生的合併結果 PEM
  final String? lastMergedCertPem;

  /// 查看詳細資訊的回呼，傳入 PEM 文字後導覽到憑證檢視畫面
  final ValueChanged<String>? onViewDetails;

  const ExportScreen({
    super.key,
    this.lastGeneratedKeyPem,
    this.lastGeneratedCACertPem,
    this.lastGeneratedCSRPem,
    this.lastIssuedCertPem,
    this.lastMergedCertPem,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // 建立可匯出項目清單
    final List<_ExportItem> items = _buildExportItems(l10n);

    // 計算可用項目數量
    final int availableCount = items.where((e) => e.pem != null).length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuExport)),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Column(
          children: [
            Expanded(
              child: items.every((e) => e.pem == null)
                  ? _buildEmptyState(l10n)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      children: [
                        // 一鍵全部儲存按鈕
                        if (availableCount > 1) ...[
                          _buildSaveAllButton(context, l10n, items),
                          const SizedBox(height: 16),
                        ],
                        // 各匯出項目卡片
                        ...items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildExportCard(context, l10n, item),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建立可匯出項目清單
  List<_ExportItem> _buildExportItems(AppLocalizations l10n) {
    // 判斷合併結果是否為 PKCS#7 格式
    final bool isMergedPkcs7 = lastMergedCertPem != null &&
        lastMergedCertPem!.contains('BEGIN PKCS7');
    final String mergedExt = isMergedPkcs7 ? 'p7b' : 'pem';

    return [
      _ExportItem(
        icon: Icons.vpn_key_outlined,
        title: l10n.exportPrivateKey,
        description: l10n.exportPrivateKeyDesc,
        pem: lastGeneratedKeyPem,
        defaultFileName: 'private_key.key',
      ),
      _ExportItem(
        icon: Icons.verified_user_outlined,
        title: l10n.exportCACert,
        description: l10n.exportCACertDesc,
        pem: lastGeneratedCACertPem,
        defaultFileName: 'ca_certificate.crt',
      ),
      _ExportItem(
        icon: Icons.description_outlined,
        title: l10n.exportCSR,
        description: l10n.exportCSRDesc,
        pem: lastGeneratedCSRPem,
        defaultFileName: 'certificate_request.csr',
      ),
      _ExportItem(
        icon: Icons.assignment_turned_in_outlined,
        title: l10n.exportIssuedCert,
        description: l10n.exportIssuedCertDesc,
        pem: lastIssuedCertPem,
        defaultFileName: 'issued_certificate.crt',
      ),
      _ExportItem(
        icon: Icons.merge_type_outlined,
        title: l10n.exportMergedChain,
        description: l10n.exportMergedChainDesc,
        pem: lastMergedCertPem,
        defaultFileName: 'cert_chain.$mergedExt',
      ),
    ];
  }

  /// 無可匯出項目時的空白狀態
  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.file_download_off_outlined,
              size: 56,
              color: AppColors.textHint.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.exportNoData,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一鍵全部儲存按鈕
  Widget _buildSaveAllButton(
    BuildContext context,
    AppLocalizations l10n,
    List<_ExportItem> items,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: () => _saveAll(context, l10n, items),
        icon: Icon(outputAllIcon, size: 20),
        label: Text(
          platformFileLabel(
            desktop: l10n.exportSaveAll,
            mobile: l10n.exportExportAll,
            web: l10n.exportDownloadAll,
          ),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }

  /// 匯出項目卡片
  Widget _buildExportCard(
    BuildContext context,
    AppLocalizations l10n,
    _ExportItem item,
  ) {
    final bool available = item.pem != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: available
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.primaryDark.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列：圖示 + 名稱 + 狀態
          Row(
            children: [
              Icon(
                item.icon,
                size: 22,
                color: available ? AppColors.success : AppColors.textHint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: available
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // 狀態標籤
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: available
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.primaryDark.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      available
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      size: 12,
                      color: available ? AppColors.success : AppColors.textHint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      available
                          ? item.defaultFileName
                          : l10n.exportNotAvailable,
                      style: TextStyle(
                        color:
                            available ? AppColors.success : AppColors.textHint,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 操作按鈕列（僅在可用時顯示）
          if (available) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _ActionChip(
                  icon: outputFileIcon,
                  label: platformFileLabel(
                    desktop: l10n.exportSave,
                    mobile: l10n.exportExportFile,
                    web: l10n.exportDownloadFile,
                  ),
                  onPressed: () =>
                      _saveFile(context, l10n, item.pem!, item.defaultFileName),
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.copy_outlined,
                  label: l10n.exportCopy,
                  onPressed: () => _copyPem(context, l10n, item.pem!),
                ),
                if (onViewDetails != null) ...[
                  const Spacer(),
                  _ActionChip(
                    icon: Icons.visibility_outlined,
                    label: l10n.selfCAViewDetails,
                    onPressed: () {
                      debugPrint('[ExportScreen] 查看詳細: ${item.title}');
                      onViewDetails!(item.pem!);
                    },
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── 操作方法 ──

  /// 複製 PEM 文字到剪貼簿
  void _copyPem(BuildContext context, AppLocalizations l10n, String pem) {
    Clipboard.setData(ClipboardData(text: pem));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.certViewCopied),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.surface,
      ),
    );
    debugPrint('[ExportScreen] 已複製到剪貼簿');
  }

  /// 輸出單一檔案（桌面儲存/行動匯出/Web 下載）
  Future<void> _saveFile(
    BuildContext context,
    AppLocalizations l10n,
    String pem,
    String defaultFileName,
  ) async {
    await outputFileWithFeedback(
      context: context,
      l10n: l10n,
      content: pem,
      defaultFileName: defaultFileName,
      debugTag: '[ExportScreen]',
    );
  }

  /// 逐一輸出所有可用項目
  Future<void> _saveAll(
    BuildContext context,
    AppLocalizations l10n,
    List<_ExportItem> items,
  ) async {
    debugPrint('[ExportScreen] 全部輸出');
    final List<_ExportItem> available =
        items.where((e) => e.pem != null).toList();

    for (final _ExportItem item in available) {
      await _saveFile(context, l10n, item.pem!, item.defaultFileName);
    }
  }
}

// ============================================================
// 匯出項目模型
// ============================================================

/// 可匯出項目的資料模型
class _ExportItem {
  final IconData icon;
  final String title;
  final String description;
  final String? pem;
  final String defaultFileName;

  const _ExportItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.pem,
    required this.defaultFileName,
  });
}

// ============================================================
// 操作按鈕（小型）
// ============================================================

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
