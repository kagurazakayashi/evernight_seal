import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/certificate_service.dart';
import '../theme/app_colors.dart';

/// 合併憑證畫面
///
/// 將多個憑證合併為 PEM 鏈或 PKCS#7 格式，
/// 可選擇性地在末尾附加私鑰。
class MergeCertScreen extends StatefulWidget {
  /// 從自簽名 CA 畫面傳遞過來的 CA 憑證 PEM
  final String? lastGeneratedCACertPem;

  /// 從簽發憑證畫面傳遞過來的已簽發憑證 PEM
  final String? lastIssuedCertPem;

  /// 從建立私鑰畫面傳遞過來的已產生私鑰 PEM
  final String? lastGeneratedKeyPem;

  /// 查看詳細資訊的回呼
  final ValueChanged<String>? onViewDetails;

  /// 當合併完成時回呼，傳出合併結果 PEM 文字
  final ValueChanged<String?>? onMerged;

  const MergeCertScreen({
    super.key,
    this.lastGeneratedCACertPem,
    this.lastIssuedCertPem,
    this.lastGeneratedKeyPem,
    this.onViewDetails,
    this.onMerged,
  });

  @override
  State<MergeCertScreen> createState() => _MergeCertScreenState();
}

/// 單一憑證條目模型
class _CertEntry {
  String? pem;
  String? cn;
}

class _MergeCertScreenState extends State<MergeCertScreen> {
  // ── 憑證列表 ──
  final List<_CertEntry> _certEntries = [_CertEntry()];

  // ── 私鑰（選用） ──
  bool _includeKey = false;
  String? _privateKeyPem;
  String? _detectedKeyType;

  // ── 輸出格式 ──
  String _outputFormat = 'PEM'; // 'PEM' or 'PKCS7'

  // ── 結果狀態 ──
  String? _resultPem;
  String? _errorMessage;

  /// 檢查是否有外部傳入的值可用
  bool get _hasLastCACert =>
      widget.lastGeneratedCACertPem != null &&
      widget.lastGeneratedCACertPem!.isNotEmpty;
  bool get _hasLastIssuedCert =>
      widget.lastIssuedCertPem != null &&
      widget.lastIssuedCertPem!.isNotEmpty;
  bool get _hasLastKey =>
      widget.lastGeneratedKeyPem != null &&
      widget.lastGeneratedKeyPem!.isNotEmpty;

  /// 是否有任何外部傳入的值可用（用於一鍵載入按鈕）
  bool get _hasAnyRecent =>
      _hasLastIssuedCert || _hasLastCACert || _hasLastKey;

  /// 一鍵載入所有可用的最近產生項目
  ///
  /// 依照典型 PEM 鏈順序載入：終端憑證 → CA 憑證 → 私鑰。
  void _loadAllRecent() {
    debugPrint('[MergeCertScreen] 一鍵載入全部: '
        'issuedCert=$_hasLastIssuedCert, '
        'caCert=$_hasLastCACert, '
        'key=$_hasLastKey');

    setState(() {
      // 重設憑證列表
      _certEntries.clear();

      // 依照鏈順序加入：終端憑證在前，CA 憑證在後
      if (_hasLastIssuedCert) {
        final entry = _CertEntry()
          ..pem = widget.lastIssuedCertPem
          ..cn = _parseCertCN(widget.lastIssuedCertPem!);
        _certEntries.add(entry);
        debugPrint('[MergeCertScreen] 已載入已簽發憑證');
      }

      if (_hasLastCACert) {
        final entry = _CertEntry()
          ..pem = widget.lastGeneratedCACertPem
          ..cn = _parseCertCN(widget.lastGeneratedCACertPem!);
        _certEntries.add(entry);
        debugPrint('[MergeCertScreen] 已載入 CA 憑證');
      }

      // 若無任何憑證可載入，保留一個空白條目
      if (_certEntries.isEmpty) {
        _certEntries.add(_CertEntry());
      }

      // 載入私鑰（若可用）
      if (_hasLastKey) {
        _privateKeyPem = widget.lastGeneratedKeyPem;
        try {
          final info =
              CertificateService.parsePrivateKeyPem(widget.lastGeneratedKeyPem!);
          _detectedKeyType = info?.algorithm;
        } catch (_) {
          _detectedKeyType = 'Unknown';
        }
        debugPrint('[MergeCertScreen] 已載入私鑰');
      }
    });
  }

  // ── 解析憑證 CN ──

  String? _parseCertCN(String pem) {
    try {
      final cert = X509Utils.x509CertificateFromPem(pem);
      return CertificateService.getSubjectCN(cert);
    } catch (_) {
      return 'Unknown';
    }
  }

  void _loadCertEntry(int index, String pem) {
    debugPrint('[MergeCertScreen] 載入憑證 #$index: ${pem.length} 字元');
    setState(() {
      _certEntries[index].pem = pem;
      _certEntries[index].cn = _parseCertCN(pem);
    });
  }

  Future<void> _loadCertFromFile(int index) async {
    debugPrint('[MergeCertScreen] 開啟憑證檔案 #$index');
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: l10n.dialogOpenCertFile,
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;

      String pem;
      try {
        pem = utf8.decode(bytes);
      } catch (_) {
        setState(() => _errorMessage = l10n.errorReadFileText);
        return;
      }

      if (!pem.contains('BEGIN CERTIFICATE')) {
        setState(
            () => _errorMessage = l10n.errorNoCertInFile);
        return;
      }

      _loadCertEntry(index, pem);
    } catch (e) {
      debugPrint('[MergeCertScreen] 載入憑證檔案失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  void _clearCertEntry(int index) {
    debugPrint('[MergeCertScreen] 清除憑證 #$index');
    setState(() {
      _certEntries[index].pem = null;
      _certEntries[index].cn = null;
    });
  }

  void _removeCertEntry(int index) {
    debugPrint('[MergeCertScreen] 移除憑證 #$index');
    setState(() => _certEntries.removeAt(index));
  }

  void _addCertEntry({String? pem}) {
    debugPrint('[MergeCertScreen] 新增憑證條目');
    final entry = _CertEntry();
    if (pem != null) {
      entry.pem = pem;
      entry.cn = _parseCertCN(pem);
    }
    setState(() => _certEntries.add(entry));
  }

  /// 一鍵移除全部：清空所有憑證條目、私鑰及結果
  void _clearAll() {
    debugPrint('[MergeCertScreen] 清除所有欄位');
    setState(() {
      _certEntries
        ..clear()
        ..add(_CertEntry());
      _includeKey = false;
      _privateKeyPem = null;
      _detectedKeyType = null;
      _outputFormat = 'PEM';
      _resultPem = null;
      _errorMessage = null;
    });
    widget.onMerged?.call(null);
  }

  // ── 私鑰載入 ──

  void _loadKeyFromPem(String pem) {
    debugPrint('[MergeCertScreen] 載入私鑰: ${pem.length} 字元');
    setState(() {
      _privateKeyPem = pem;
      try {
        final info = CertificateService.parsePrivateKeyPem(pem);
        _detectedKeyType = info?.algorithm;
      } catch (_) {
        _detectedKeyType = 'Unknown';
      }
    });
  }

  Future<void> _loadKeyFromFile() async {
    debugPrint('[MergeCertScreen] 開啟私鑰檔案');
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: l10n.dialogOpenKeyFile,
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;

      String pem;
      try {
        pem = utf8.decode(bytes);
      } catch (_) {
        setState(() => _errorMessage = l10n.errorReadFileText);
        return;
      }

      if (!CertificateService.hasPrivateKeyPem(pem)) {
        setState(
            () => _errorMessage = l10n.errorNoKeyInFile);
        return;
      }

      _loadKeyFromPem(pem);
    } catch (e) {
      debugPrint('[MergeCertScreen] 載入私鑰失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  void _clearKey() {
    debugPrint('[MergeCertScreen] 清除私鑰');
    setState(() {
      _privateKeyPem = null;
      _detectedKeyType = null;
    });
  }

  // ── 合併 ──

  void _merge() {
    final l10n = AppLocalizations.of(context);
    debugPrint('[MergeCertScreen] 合併: format=$_outputFormat, '
        'entries=${_certEntries.length}, includeKey=$_includeKey');

    // 收集已載入的憑證 PEM
    final loadedPems = _certEntries
        .where((e) => e.pem != null && e.pem!.isNotEmpty)
        .map((e) => e.pem!)
        .toList();

    if (loadedPems.isEmpty) {
      setState(() => _errorMessage = l10n.mergeCertNoCerts);
      return;
    }

    setState(() {
      _errorMessage = null;
      _resultPem = null;
    });

    try {
      String result;

      if (_outputFormat == 'PKCS7') {
        // PKCS#7 格式不支援私鑰
        result = X509Utils.pemToPkcs7(loadedPems);
        debugPrint('[MergeCertScreen] 產生 PKCS#7: ${loadedPems.length} 個憑證');
      } else {
        // PEM 鏈：串接所有憑證 PEM
        final buf = StringBuffer();
        for (final pem in loadedPems) {
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(pem.trim());
        }
        // 附加私鑰（若啟用）
        if (_includeKey && _privateKeyPem != null) {
          buf.write('\n');
          buf.write(_privateKeyPem!.trim());
          debugPrint('[MergeCertScreen] 已附加私鑰');
        }
        result = buf.toString();
        debugPrint('[MergeCertScreen] 產生 PEM 鏈: ${loadedPems.length} 個憑證');
      }

      setState(() => _resultPem = result);
      widget.onMerged?.call(result);
      debugPrint('[MergeCertScreen] 合併完成');
    } catch (e) {
      debugPrint('[MergeCertScreen] 合併失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  // ── 操作輔助 ──

  void _copyResult(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.certViewCopied),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.surface,
      ),
    );
    debugPrint('[MergeCertScreen] 已複製到剪貼簿');
  }

  Future<void> _saveResult(String text) async {
    final ext = _outputFormat == 'PKCS7' ? 'p7b' : 'pem';
    final defaultName = 'merged_chain.$ext';
    debugPrint('[MergeCertScreen] 儲存檔案: $defaultName');
    final l10n = AppLocalizations.of(context);

    try {
      final bytes = utf8.encode(text);
      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: l10n.dialogSaveFile,
        fileName: defaultName,
        type: FileType.any,
        bytes: bytes,
      );

      if (outputPath != null && outputPath.isNotEmpty) {
        debugPrint('[MergeCertScreen] 已儲存至: $outputPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.savedToPath(outputPath)),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.surface,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[MergeCertScreen] 儲存失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.saveFailed(e.toString())),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuMergeCert),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all_outlined),
            tooltip: l10n.certViewClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  // ── 憑證列表 ──
                  _buildSectionHeader(l10n.mergeCertSectionCerts),
                  const SizedBox(height: 8),
                  _buildQuickAddButtons(l10n),
                  const SizedBox(height: 8),
                  ..._buildCertEntries(l10n),
                  _buildAddEntryButton(l10n),

                  // ── 私鑰（選用） ──
                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.mergeCertSectionKey),
                  const SizedBox(height: 8),
                  _buildPrivateKeySection(l10n),

                  // ── 輸出格式 ──
                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.mergeCertSectionOutput),
                  const SizedBox(height: 8),
                  _buildOutputFormatSelector(l10n),

                  // ── 合併按鈕 ──
                  const SizedBox(height: 16),
                  _buildMergeButton(l10n),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(l10n),
                  ],
                  if (_resultPem != null) ...[
                    const SizedBox(height: 16),
                    _buildResultSection(l10n),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 通用 UI ──

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryDark.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          if (required)
            const Text(
              ' *',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  // ── 快速新增按鈕 ──

  Widget _buildQuickAddButtons(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        // 一鍵載入全部按鈕
        if (_hasAnyRecent)
          _AccentButton(
            icon: Icons.auto_awesome,
            label: l10n.mergeCertLoadAllRecent,
            onPressed: _loadAllRecent,
          )
        else
          Opacity(
            opacity: 0.4,
            child: _SmallOutlineButton(
              icon: Icons.auto_awesome,
              label: l10n.mergeCertLoadAllRecent,
              onPressed: null,
            ),
          ),
        // 個別載入按鈕
        if (_hasLastIssuedCert)
          _AccentButton(
            icon: Icons.add_circle_outline,
            label: l10n.mergeCertUseLastIssuedCert,
            onPressed: () {
              debugPrint('[MergeCertScreen] 快速新增已簽發憑證');
              _addCertEntry(pem: widget.lastIssuedCertPem);
            },
          ),
        if (_hasLastCACert)
          _AccentButton(
            icon: Icons.add_circle_outline,
            label: l10n.mergeCertUseLastCACert,
            onPressed: () {
              debugPrint('[MergeCertScreen] 快速新增 CA 憑證');
              _addCertEntry(pem: widget.lastGeneratedCACertPem);
            },
          ),
        // 一鍵移除全部
        _SmallOutlineButton(
          icon: Icons.delete_sweep_outlined,
          label: l10n.mergeCertClearAll,
          onPressed: _clearAll,
        ),
      ],
    );
  }

  // ── 憑證條目列表 ──

  List<Widget> _buildCertEntries(AppLocalizations l10n) {
    return _certEntries.asMap().entries.map((e) {
      final idx = e.key;
      final entry = e.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildCertEntryCard(l10n, idx, entry),
      );
    }).toList();
  }

  Widget _buildCertEntryCard(AppLocalizations l10n, int index, _CertEntry entry) {
    final hasLoaded = entry.pem != null && entry.cn != null;

    if (hasLoaded) {
      // 已載入：顯示摘要卡片
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.success.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_outlined, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.mergeCertEntry(index + 1),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.cn!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            _IconButton(
              icon: Icons.close,
              color: AppColors.textHint,
              size: 18,
              onTap: () => _clearCertEntry(index),
            ),
            if (_certEntries.length > 1) ...[
              const SizedBox(width: 4),
              _IconButton(
                icon: Icons.remove_circle_outline,
                color: AppColors.error.withValues(alpha: 0.7),
                size: 18,
                onTap: () => _removeCertEntry(index),
              ),
            ],
          ],
        ),
      );
    }

    // 尚未載入：顯示輸入區域
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primaryDark.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mergeCertEntry(index + 1),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SmallOutlineButton(
                icon: Icons.file_open_outlined,
                label: l10n.mergeCertLoadFile,
                onPressed: () => _loadCertFromFile(index),
              ),
              if (_certEntries.length > 1) ...[
                const SizedBox(width: 4),
                _IconButton(
                  icon: Icons.remove_circle_outline,
                  color: AppColors.textHint,
                  size: 18,
                  onTap: () => _removeCertEntry(index),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: TextField(
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: l10n.mergeCertHint,
                hintStyle: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                    color: AppColors.primaryDark.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                    color: AppColors.primaryDark.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
              ),
              onChanged: (text) {
                if (text.contains('BEGIN CERTIFICATE')) {
                  _loadCertEntry(index, text);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddEntryButton(AppLocalizations l10n) {
    return _SmallOutlineButton(
      icon: Icons.add_outlined,
      label: l10n.mergeCertAddEntry,
      onPressed: () => _addCertEntry(),
    );
  }

  // ── 私鑰區塊 ──

  Widget _buildPrivateKeySection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 啟用/停用切換
        GestureDetector(
          onTap: () {
            debugPrint('[MergeCertScreen] 切換包含私鑰: ${!_includeKey}');
            setState(() {
              _includeKey = !_includeKey;
              if (!_includeKey) {
                _privateKeyPem = null;
                _detectedKeyType = null;
              }
            });
          },
          child: Row(
            children: [
              Icon(
                _includeKey ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: _includeKey ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.mergeCertIncludeKey,
                style: TextStyle(
                  color: _includeKey ? AppColors.textPrimary : AppColors.textHint,
                  fontSize: 13,
                  fontWeight: _includeKey ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (_outputFormat == 'PKCS7') ...[
                const SizedBox(width: 8),
                Text(
                  l10n.naForPKCS7,
                  style: TextStyle(
                    color: AppColors.textHint.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_includeKey && _outputFormat != 'PKCS7') ...[
          const SizedBox(height: 8),
          _buildPrivateKeyInput(l10n),
        ],
      ],
    );
  }

  Widget _buildPrivateKeyInput(AppLocalizations l10n) {
    if (_privateKeyPem != null && _detectedKeyType != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.success.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.vpn_key, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n.selfCAKeyLoaded} ($_detectedKeyType)',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SmallOutlineButton(
              icon: Icons.file_open_outlined,
              label: l10n.selfCAPrivateKeyLoad,
              onPressed: _loadKeyFromFile,
            ),
            const SizedBox(width: 6),
            _IconButton(
              icon: Icons.close,
              color: AppColors.textHint,
              size: 18,
              onTap: _clearKey,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFieldLabel(l10n.selfCAPrivateKey),
            ),
            if (_hasLastKey)
              _AccentButton(
                icon: Icons.swap_horiz_outlined,
                label: l10n.issueCertUseLastKey,
                onPressed: () {
                  debugPrint('[MergeCertScreen] 載入剛剛建立的私鑰');
                  final pem = widget.lastGeneratedKeyPem;
                  if (pem != null && pem.isNotEmpty) _loadKeyFromPem(pem);
                },
              )
            else
              Opacity(
                opacity: 0.4,
                child: _SmallOutlineButton(
                  icon: Icons.swap_horiz_outlined,
                  label: l10n.issueCertUseLastKey,
                  onPressed: null,
                ),
              ),
            const SizedBox(width: 6),
            _SmallOutlineButton(
              icon: Icons.file_open_outlined,
              label: l10n.selfCAPrivateKeyLoad,
              onPressed: _loadKeyFromFile,
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 70,
          child: TextField(
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: l10n.selfCAPrivateKeyHint,
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: AppColors.primaryDark.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: AppColors.primaryDark.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
            ),
            onChanged: (text) {
              if (CertificateService.hasPrivateKeyPem(text)) {
                _loadKeyFromPem(text);
              }
            },
          ),
        ),
      ],
    );
  }

  // ── 輸出格式選擇器 ──

  Widget _buildOutputFormatSelector(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _FormatCard(
            label: l10n.mergeCertFormatPEM,
            icon: Icons.text_snippet_outlined,
            isSelected: _outputFormat == 'PEM',
            onTap: () {
              debugPrint('[MergeCertScreen] 選擇輸出格式: PEM');
              setState(() => _outputFormat = 'PEM');
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FormatCard(
            label: l10n.mergeCertFormatPKCS7,
            icon: Icons.archive_outlined,
            isSelected: _outputFormat == 'PKCS7',
            onTap: () {
              debugPrint('[MergeCertScreen] 選擇輸出格式: PKCS7');
              setState(() => _outputFormat = 'PKCS7');
            },
          ),
        ),
      ],
    );
  }

  // ── 合併按鈕 ──

  Widget _buildMergeButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _merge,
        icon: const Icon(Icons.merge_type_outlined, size: 20),
        label: Text(
          l10n.mergeCertMerge,
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

  // ── 錯誤提示 ──

  Widget _buildErrorBanner(AppLocalizations l10n) {
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
              '${l10n.certViewError}: $_errorMessage',
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _errorMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: AppColors.error,
          ),
        ],
      ),
    );
  }

  // ── 結果區塊 ──

  Widget _buildResultSection(AppLocalizations l10n) {
    final result = _resultPem!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              l10n.mergeCertResultTitle,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 280),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.primaryDark.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              result,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            _ActionChip(
              icon: Icons.copy_outlined,
              label: l10n.mergeCertCopyResult,
              onPressed: () => _copyResult(result),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.save_outlined,
              label: l10n.mergeCertSaveResult,
              onPressed: () => _saveResult(result),
            ),
            if (widget.onViewDetails != null) ...[
              const Spacer(),
              _ActionChip(
                icon: Icons.visibility_outlined,
                label: l10n.selfCAViewDetails,
                onPressed: () => widget.onViewDetails!(result),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ============================================================
// 共用私有元件
// ============================================================

class _FormatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FormatCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isSelected ? AppColors.primary : AppColors.primaryDark.withValues(alpha: 0.3);
    final bgColor = isSelected
        ? AppColors.primary.withValues(alpha: 0.15)
        : AppColors.surface;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: isSelected ? 1 : 0.5),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.glow, blurRadius: 6, offset: const Offset(0, 2))]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: isSelected ? AppColors.primary : AppColors.textHint),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 14,
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

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.color,
    this.size = 20,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

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
