import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/certificate_service.dart';
import '../theme/app_colors.dart';

/// 驗證校驗畫面 - 驗證憑證與私鑰是否為配對的金鑰對
class VerifyScreen extends StatefulWidget {
  /// 從建立私鑰畫面傳遞過來的已產生私鑰 PEM
  final String? lastGeneratedKeyPem;

  /// 從合併憑證畫面傳遞過來的合併結果 PEM
  final String? lastMergedCertPem;

  const VerifyScreen({
    super.key,
    this.lastGeneratedKeyPem,
    this.lastMergedCertPem,
  });

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final TextEditingController _certController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();

  String? _certFileName;
  String? _keyFileName;
  bool _isVerifying = false;

  /// 解析出的憑證（第一張，用於比對）
  X509CertificateData? _parsedCert;

  /// 比對結果
  KeyPairMatchResult? _matchResult;

  /// 錯誤訊息
  String? _errorMessage;

  @override
  void dispose() {
    _certController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  // ---- 憑證載入 ----

  Future<void> _pickCertFile() async {
    debugPrint('[VerifyScreen] 選擇憑證檔案');
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'crt', 'cer', 'der', 'p7b', 'p7c'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      debugPrint('[VerifyScreen] 憑證檔案: ${file.name} (${bytes.length} bytes)');

      // 嘗試解碼為文字
      String pemText;
      try {
        pemText = utf8.decode(bytes);
      } catch (_) {
        // DER 格式 → 包裝為 PEM
        pemText = '-----BEGIN CERTIFICATE-----\n'
            '${base64.encode(bytes)}\n'
            '-----END CERTIFICATE-----';
      }

      setState(() {
        _certController.text = pemText;
        _certFileName = file.name;
        _matchResult = null;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('[VerifyScreen] 憑證檔案載入錯誤: $e');
    }
  }

  Future<void> _pickKeyFile() async {
    debugPrint('[VerifyScreen] 選擇私鑰檔案');
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'key'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      debugPrint('[VerifyScreen] 私鑰檔案: ${file.name} (${bytes.length} bytes)');

      final pemText = utf8.decode(bytes);
      setState(() {
        _keyController.text = pemText;
        _keyFileName = file.name;
        _matchResult = null;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('[VerifyScreen] 私鑰檔案載入錯誤: $e');
    }
  }

  // ---- 驗證邏輯 ----

  void _verify() {
    final certText = _certController.text.trim().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final keyText = _keyController.text.trim().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    debugPrint('[VerifyScreen] 開始驗證: cert=${certText.length} chars, key=${keyText.length} chars');

    if (certText.isEmpty || keyText.isEmpty) {
      setState(() {
        _errorMessage = 'Both certificate and private key are required';
        _matchResult = null;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _matchResult = null;
    });

    try {
      // 解析憑證
      final certResult = CertificateService.parsePemText(certText);
      if (!certResult.isSuccess || certResult.certificates.isEmpty) {
        setState(() {
          _errorMessage = certResult.errorMessage ?? 'Failed to parse certificate';
          _isVerifying = false;
        });
        return;
      }

      final cert = certResult.certificates.first;
      _parsedCert = cert;

      // 檢查私鑰
      if (!CertificateService.hasPrivateKeyPem(keyText)) {
        setState(() {
          _errorMessage = 'No private key found in the input';
          _isVerifying = false;
        });
        return;
      }

      // 提取私鑰 PEM 區塊
      final keyBlocks = CertificateService.extractPrivateKeyBlocks(keyText);
      if (keyBlocks.isEmpty) {
        setState(() {
          _errorMessage = 'Failed to extract private key block';
          _isVerifying = false;
        });
        return;
      }

      // 執行配對比對
      final result = CertificateService.matchKeyPair(
        cert: cert,
        privateKeyPem: keyBlocks.first,
      );

      debugPrint('[VerifyScreen] 比對結果: ${result.status}, msg=${result.message}');

      setState(() {
        _matchResult = result;
        _isVerifying = false;
      });
    } catch (e) {
      debugPrint('[VerifyScreen] 驗證錯誤: $e');
      setState(() {
        _errorMessage = e.toString();
        _isVerifying = false;
      });
    }
  }

  void _clearAll() {
    debugPrint('[VerifyScreen] 清除所有資料');
    setState(() {
      _certController.clear();
      _keyController.clear();
      _certFileName = null;
      _keyFileName = null;
      _matchResult = null;
      _errorMessage = null;
      _parsedCert = null;
    });
  }

  // ---- 快速操作 ----

  /// 是否有合併憑證可用
  bool get _hasMergedCert =>
      widget.lastMergedCertPem != null &&
      widget.lastMergedCertPem!.isNotEmpty;

  /// 是否有已建立私鑰可用
  bool get _hasCreatedKey =>
      widget.lastGeneratedKeyPem != null &&
      widget.lastGeneratedKeyPem!.isNotEmpty;

  /// 是否有任何可用的外部傳入值
  bool get _hasAnyRecent => _hasMergedCert || _hasCreatedKey;

  /// 使用合併後的憑證
  void _useMergedCert() {
    if (!_hasMergedCert) return;
    debugPrint('[VerifyScreen] 載入合併憑證');
    setState(() {
      _certController.text = widget.lastMergedCertPem!;
      _certFileName = null;
      _matchResult = null;
      _errorMessage = null;
    });
  }

  /// 使用已建立的私鑰
  void _useCreatedKey() {
    if (!_hasCreatedKey) return;
    debugPrint('[VerifyScreen] 載入已建立私鑰');
    setState(() {
      _keyController.text = widget.lastGeneratedKeyPem!;
      _keyFileName = null;
      _matchResult = null;
      _errorMessage = null;
    });
  }

  /// 一鍵載入全部可用項目
  void _loadAllRecent() {
    debugPrint('[VerifyScreen] 一鍵載入全部: '
        'mergedCert=$_hasMergedCert, key=$_hasCreatedKey');
    if (_hasMergedCert) _useMergedCert();
    if (_hasCreatedKey) _useCreatedKey();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuVerify),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all_outlined),
            tooltip: l10n.verifyClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: _isVerifying
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 快速操作按鈕
                  _buildQuickActionButtons(l10n),
                  const SizedBox(height: 12),

                  // 憑證輸入區
                  _buildInputCard(
                    icon: Icons.verified_outlined,
                    title: l10n.verifySectionCert,
                    controller: _certController,
                    hint: l10n.verifyCertHint,
                    fileName: _certFileName,
                    loadedLabel: l10n.verifyCertLoaded,
                    onPickFile: _pickCertFile,
                    loadFileLabel: l10n.verifyLoadCertFile,
                    useLastLabel: l10n.verifyUseMergedCert,
                    onUseLast: _useMergedCert,
                    hasLast: _hasMergedCert,
                  ),
                  const SizedBox(height: 12),

                  // 私鑰輸入區
                  _buildInputCard(
                    icon: Icons.vpn_key_outlined,
                    title: l10n.verifySectionKey,
                    controller: _keyController,
                    hint: l10n.verifyKeyHint,
                    fileName: _keyFileName,
                    loadedLabel: l10n.verifyKeyLoaded,
                    onPickFile: _pickKeyFile,
                    loadFileLabel: l10n.verifyLoadKeyFile,
                    useLastLabel: l10n.verifyUseCreatedKey,
                    onUseLast: _useCreatedKey,
                    hasLast: _hasCreatedKey,
                  ),
                  const SizedBox(height: 16),

                  // 驗證按鈕
                  _buildVerifyButton(l10n),
                  const SizedBox(height: 16),

                  // 結果顯示
                  if (_errorMessage != null) _buildErrorCard(l10n),
                  if (_matchResult != null) _buildResultCard(l10n),
                ],
              ),
      ),
    );
  }

  Widget _buildInputCard({
    required IconData icon,
    required String title,
    required TextEditingController controller,
    required String hint,
    required String? fileName,
    required String loadedLabel,
    required VoidCallback onPickFile,
    required String loadFileLabel,
    String? useLastLabel,
    VoidCallback? onUseLast,
    bool hasLast = false,
  }) {
    final bool hasContent = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasContent
              ? AppColors.primaryDark
              : AppColors.primaryDark.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (hasContent)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      fileName ?? loadedLabel,
                      style: const TextStyle(color: AppColors.success, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 文字輸入區
          TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 11),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
            ),
            onChanged: (_) => setState(() {
              _matchResult = null;
              _errorMessage = null;
            }),
          ),
          const SizedBox(height: 8),

          // 按鈕列：「使用上次」+「開啟檔案」（右對齊）
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (useLastLabel != null) ...[
                hasLast && onUseLast != null
                    ? _AccentButton(
                        icon: Icons.history,
                        label: useLastLabel,
                        onPressed: onUseLast,
                      )
                    : Opacity(
                        opacity: 0.4,
                        child: _SmallOutlineButton(
                          icon: Icons.history,
                          label: useLastLabel,
                          onPressed: null,
                        ),
                      ),
                const SizedBox(width: 8),
              ],
              Material(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: onPickFile,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.file_open_outlined, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          loadFileLabel,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _verify,
        icon: const Icon(Icons.shield_outlined, size: 20),
        label: Text(
          l10n.verifyButton,
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

  Widget _buildQuickActionButtons(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        // 一鍵載入全部
        if (_hasAnyRecent)
          _AccentButton(
            icon: Icons.auto_awesome,
            label: l10n.verifyLoadAllRecent,
            onPressed: _loadAllRecent,
          )
        else
          Opacity(
            opacity: 0.4,
            child: _SmallOutlineButton(
              icon: Icons.auto_awesome,
              label: l10n.verifyLoadAllRecent,
              onPressed: null,
            ),
          ),
        // 一鍵移除全部
        _SmallOutlineButton(
          icon: Icons.delete_sweep_outlined,
          label: l10n.verifyClearAll,
          onPressed: _clearAll,
        ),
      ],
    );
  }

  Widget _buildResultCard(AppLocalizations l10n) {
    final result = _matchResult!;
    final bool isMatched = result.status == KeyMatchStatus.matched;
    final bool isError = result.status == KeyMatchStatus.error;

    final Color statusColor = isMatched
        ? AppColors.success
        : isError
            ? AppColors.warning
            : AppColors.error;
    final IconData statusIcon = isMatched
        ? Icons.check_circle_outlined
        : isError
            ? Icons.help_outline
            : Icons.cancel_outlined;
    final String statusText = isMatched
        ? l10n.verifyResultMatched
        : isError
            ? l10n.verifyResultError
            : l10n.verifyResultMismatched;
    final String statusDesc = isMatched
        ? l10n.verifyMatchedDesc
        : isError
            ? (result.message ?? '')
            : l10n.verifyMismatchedDesc;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 狀態標題
          Row(
            children: [
              Icon(statusIcon, size: 28, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusDesc,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 詳細資訊
          if (result.certAlgorithm != null || result.keyAlgorithm != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.primaryDark),
            const SizedBox(height: 12),

            // 演算法
            if (result.certAlgorithm != null)
              _buildDetailRow(
                l10n.verifyCertInfo,
                '${result.certAlgorithm}'
                    '${result.certKeySize != null ? ' (${result.certKeySize} bits)' : ''}',
              ),
            if (result.keyAlgorithm != null) ...[
              const SizedBox(height: 4),
              _buildDetailRow(
                l10n.verifyKeyInfo,
                '${result.keyAlgorithm}'
                    '${result.keyKeySize != null ? ' (${result.keyKeySize} bits)' : ''}',
              ),
            ],

            // 憑證主體
            if (_parsedCert != null) ...[
              const SizedBox(height: 4),
              _buildDetailRow(
                l10n.certViewSubject,
                CertificateService.getSubjectCN(_parsedCert!),
              ),
            ],
          ],

          // 不匹配時顯示具體原因
          if (!isMatched && result.message != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.message!,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 快速操作按鈕元件
// ============================================================

/// 強調按鈕（用於快速載入操作）
class _AccentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AccentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.textPrimary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 輪廓按鈕（用於清除等次要操作）
class _SmallOutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _SmallOutlineButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.primaryDark.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textHint,
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
