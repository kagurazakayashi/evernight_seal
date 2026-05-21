import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/certificate_service.dart';
import '../theme/app_colors.dart';

/// 查看憑證資訊畫面
class CertViewScreen extends StatefulWidget {
  const CertViewScreen({super.key});

  @override
  State<CertViewScreen> createState() => CertViewScreenState();
}

class CertViewScreenState extends State<CertViewScreen> {
  final TextEditingController _pemController = TextEditingController();

  CertParseResult? _result;
  PrivateKeyInfo? _privateKey;
  KeyPairMatchResult? _keyMatchResult;
  String? _errorMessage;
  bool _isLoading = false;
  String? _loadedFileName;
  Uint8List? _rawFileBytes;
  bool _showPasteArea = false;

  /// 目前展開的憑證索引集合
  final Set<int> _expandedIndices = {};

  /// 供外部導覽呼叫：設定 PEM 文字並自動解析
  void viewPem(String pem) {
    debugPrint('[CertViewScreen] 外部導覽檢視 PEM (${pem.length} 字元)');
    debugPrint('[CertViewScreen] PEM 前 80 字元: ${pem.substring(0, pem.length < 80 ? pem.length : 80)}');
    _pemController.text = pem;
    // 將原始 PEM 直接傳入解析，不依賴 controller.text
    _parsePemText(pem.trim());
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pemController.dispose();
    super.dispose();
  }

  // ---- 解析邏輯 ----

  void _parsePemText([String? rawInput]) {
    final input = rawInput ?? _pemController.text.trim();
    if (input.isEmpty) return;

    // 正規化換行符號：\r\n / \r → \n，避免 Windows 剪貼簿或行尾格式干擾
    final text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    debugPrint('[CertViewScreen] 解析 PEM 文字 (${text.length} 字元)');
    // 手動檢查 PEM 區塊
    final containsBegin = text.contains('-----BEGIN CERTIFICATE-----');
    final containsEnd = text.contains('-----END CERTIFICATE-----');
    debugPrint('[CertViewScreen] 含 BEGIN: $containsBegin, 含 END: $containsEnd');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = CertificateService.parsePemText(text);
      final pk = _tryParsePrivateKey(text);
      debugPrint('[CertViewScreen] 解析結果: isSuccess=${result.isSuccess}, '
          'certCount=${result.certificates.length}, '
          'error=${result.errorMessage}, hasPk=${pk != null}');
      setState(() {
        _result = result.isSuccess ? result : null;
        // 若有私鑰但無證書，不顯示證書解析錯誤
        _errorMessage = (pk != null && !result.isSuccess)
            ? null
            : result.errorMessage;
        _isLoading = false;
        _loadedFileName = null;
        _rawFileBytes = null;
        _expandedIndices.clear();
        _privateKey = pk;
        _computeKeyMatch();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndParseFile() async {
    final l10n = AppLocalizations.of(context);
    debugPrint('[CertViewScreen] 開啟檔案選擇器');

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pem', 'crt', 'cer', 'der',
          'pfx', 'p12',
          'key', 'csr',
          'p7b', 'p7c',
        ],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        debugPrint('[CertViewScreen] 使用者取消檔案選擇');
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _errorMessage = l10n.errorReadFile);
        return;
      }

      debugPrint(
        '[CertViewScreen] 已選擇檔案: ${file.name} (${bytes.length} bytes)',
      );

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _loadedFileName = file.name;
        _rawFileBytes = bytes;
      });

      _parseFileBytes(bytes, file.name);
    } catch (e) {
      setState(() {
        _errorMessage = l10n.errorFilePicker(e.toString());
        _isLoading = false;
      });
    }
  }

  void _parseFileBytes(Uint8List bytes, String fileName) {
    final ext = fileName.toLowerCase();

    // 檢查是否為 PFX/P12 → 直接彈出密碼對話框
    if (ext.endsWith('.pfx') || ext.endsWith('.p12')) {
      debugPrint('[CertViewScreen] 偵測到 PFX/P12 格式，彈出密碼對話框');
      setState(() => _isLoading = false);
      _showPasswordDialog((password) {
        _parsePfxWithPassword(password);
      });
      return;
    }

    // 先嘗試作為 PEM 文字解析
    try {
      final text = utf8.decode(bytes);
      if (CertificateService.isPrivateKeyEncrypted(text)) {
        debugPrint('[CertViewScreen] 偵測到加密私鑰，彈出密碼對話框');
        setState(() => _isLoading = false);
        _showPasswordDialog((password) {
          _parseEncryptedPemBytes(bytes, password);
        });
        return;
      }
    } catch (_) {}

    // 嘗試自動解析
    final parseResult = CertificateService.autoParse(bytes);
    _finishParsing(parseResult, bytes);
  }

  void _parsePfxWithPassword(String password) {
    if (_rawFileBytes == null) return;
    final effectivePassword = password.isEmpty ? null : password;

    debugPrint(
      '[CertViewScreen] 以密碼解析 PFX (密碼長度: ${password.length})',
    );

    setState(() => _isLoading = true);

    final result = CertificateService.parsePfxBytes(
      _rawFileBytes!,
      password: effectivePassword,
    );

    setState(() {
      _result = result.isSuccess ? result : null;
      _errorMessage = result.errorMessage;
      _isLoading = false;
      _expandedIndices.clear();
      _privateKey = null;
    });
  }

  void _parseEncryptedPemBytes(Uint8List bytes, String password) {
    // 對於加密的 PEM，嘗試以 PFX 方式處理，或直接嘗試解析證書部分
    debugPrint('[CertViewScreen] 嘗試解析加密 PEM');
    setState(() => _isLoading = true);

    final parseResult = CertificateService.autoParse(bytes, password: password);
    _finishParsing(parseResult, bytes);
  }

  void _finishParsing(CertParseResult parseResult, Uint8List bytes) {
    // 嘗試解析私鑰
    PrivateKeyInfo? pk;
    try {
      final text = utf8.decode(bytes);
      if (parseResult.sourceType == 'pem' ||
          parseResult.sourceType == 'pkcs7' ||
          parseResult.sourceType == 'pfx') {
        _pemController.text = text;
      }
      pk = _tryParsePrivateKey(text);
    } catch (_) {}

    setState(() {
      _result = parseResult.isSuccess ? parseResult : null;
      _errorMessage = (pk != null && !parseResult.isSuccess)
          ? null
          : parseResult.errorMessage;
      _isLoading = false;
      _expandedIndices.clear();
      _privateKey = pk;
      _computeKeyMatch();
    });
  }

  /// 彈出密碼輸入對話框
  void _showPasswordDialog(void Function(String password) onSubmit) {
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            l10n.certViewPasswordTitle,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.certViewPasswordMessage,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.certViewPassword,
                  hintStyle: const TextStyle(color: AppColors.textHint),
                ),
                onSubmitted: (value) {
                  Navigator.of(ctx).pop(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                l10n.certViewPasswordCancel,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(
                l10n.certViewPasswordConfirm,
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        );
      },
    ).then((password) {
      controller.dispose();
      if (password != null) {
        onSubmit(password);
      }
    });
  }

  /// 嘗試從 PEM 文字中解析私鑰資訊
  PrivateKeyInfo? _tryParsePrivateKey(String pemText) {
    if (!CertificateService.hasPrivateKeyPem(pemText)) return null;
    final blocks = CertificateService.extractPrivateKeyBlocks(pemText);
    if (blocks.isEmpty) return null;
    debugPrint('[CertViewScreen] 偵測到私鑰，嘗試解析');
    return CertificateService.parsePrivateKeyPem(blocks.first);
  }

  void _clearAll() {
    debugPrint('[CertViewScreen] 清除所有資料');
    setState(() {
      _pemController.clear();
      _result = null;
      _privateKey = null;
      _keyMatchResult = null;
      _errorMessage = null;
      _isLoading = false;
      _loadedFileName = null;
      _rawFileBytes = null;
      _showPasteArea = false;
      _expandedIndices.clear();
    });
  }

  /// 當同時存在憑證與私鑰時，自動計算配對結果
  void _computeKeyMatch() {
    if (_result == null ||
        _result!.certificates.isEmpty ||
        _privateKey == null ||
        _privateKey!.isEncrypted ||
        _privateKey!.pemText == null) {
      _keyMatchResult = null;
      return;
    }
    try {
      _keyMatchResult = CertificateService.matchKeyPair(
        cert: _result!.certificates.first,
        privateKeyPem: _privateKey!.pemText!,
      );
      debugPrint('[CertViewScreen] 金鑰配對: ${_keyMatchResult!.status}');
    } catch (e) {
      debugPrint('[CertViewScreen] 金鑰配對檢查失敗: $e');
      _keyMatchResult = null;
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuViewCert),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all_outlined),
            tooltip: l10n.certViewClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: Column(
          children: [
            _buildInputSection(l10n),
            Expanded(
              child: _buildBodyContent(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_result == null || _result!.certificates.isEmpty) {
      // 僅有私鑰或完全無內容
      if (_privateKey != null) {
        return ListView(
          children: [
            if (_errorMessage != null) _buildErrorBanner(l10n),
            _buildPrivateKeyCard(l10n),
          ],
        );
      }
      if (_errorMessage != null) {
        return ListView(
          children: [_buildErrorBanner(l10n), _buildEmptyState(l10n)],
        );
      }
      return _buildEmptyState(l10n);
    }

    // 有證書鏈，將錯誤提示和私鑰卡也放入可滾動區域
    return ListView(
      children: [
        if (_errorMessage != null) _buildErrorBanner(l10n),
        if (_privateKey != null) _buildPrivateKeyCard(l10n),
        _buildChainViewInline(l10n),
      ],
    );
  }

  /// 內聯版憑證鏈（用於 ListView 內，不使用 Expanded）
  Widget _buildChainViewInline(AppLocalizations l10n) {
    final certs = _result!.certificates;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 憑證鏈標題
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                l10n.certViewChain,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                l10n.certCountLabel(certs.length),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
        ),
        // 憑證列表（shrinkWrap + 禁止自身滾動，由外層 ListView 統一滾動）
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: certs.length,
          itemBuilder: (context, index) {
            return _CertChainTile(
              cert: certs[index],
              index: index,
              totalCount: certs.length,
              isExpanded: _expandedIndices.contains(index),
              onToggle: () {
                setState(() {
                  if (_expandedIndices.contains(index)) {
                    _expandedIndices.remove(index);
                  } else {
                    _expandedIndices.add(index);
                  }
                });
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildInputSection(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 按鈕列
          Row(
            children: [
              _ActionButton(
                icon: Icons.file_open_outlined,
                label: l10n.certViewOpenFile,
                onPressed: _pickAndParseFile,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: _showPasteArea
                    ? Icons.keyboard_hide_outlined
                    : Icons.paste_outlined,
                label: _showPasteArea ? l10n.certViewHide : l10n.certViewPaste,
                onPressed: () {
                  setState(() => _showPasteArea = !_showPasteArea);
                },
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.play_arrow_outlined,
                label: l10n.certViewParse,
                primary: true,
                onPressed: _parsePemText,
              ),
              const Spacer(),
              if (_loadedFileName != null)
                Flexible(
                  child: Text(
                    _loadedFileName!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),

          // 貼上區域（可折疊）
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _pemController,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: l10n.certViewPasteHint,
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            crossFadeState: _showPasteArea
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateKeyCard(AppLocalizations l10n) {
    final pk = _privateKey!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                l10n.certViewPrivateKey,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 金鑰配對匹配徽章
              if (_keyMatchResult != null)
                _buildMatchBadge(l10n, _keyMatchResult!),
            ],
          ),
          const SizedBox(height: 8),
          if (pk.isEncrypted) ...[
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  l10n.certViewEncrypted,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
              ],
            ),
          ] else ...[
            _DetailRow(label: l10n.certViewPrivateKeyType, value: pk.algorithm),
            if (pk.keySize != null) ...[
              const SizedBox(height: 4),
              _DetailRow(label: l10n.certViewPrivateKeySize, value: l10n.bitsSuffix(pk.keySize!)),
            ],
            if (pk.curveName != null) ...[
              const SizedBox(height: 4),
              _DetailRow(label: l10n.certViewCurve, value: pk.curveName!),
            ],
            if (pk.modulusHex != null) ...[
              const SizedBox(height: 4),
              _DetailRow(
                label: l10n.certViewModulus,
                value: _fmtHex(pk.modulusHex!),
                mono: true,
              ),
            ],
            if (pk.publicExponent != null) ...[
              const SizedBox(height: 4),
              _DetailRow(label: l10n.certViewExponent, value: pk.publicExponent.toString()),
            ],
          ],
        ],
      ),
    );
  }

  /// 建構金鑰配對匹配狀態徽章
  Widget _buildMatchBadge(AppLocalizations l10n, KeyPairMatchResult result) {
    final bool isMatched = result.status == KeyMatchStatus.matched;
    final bool isError = result.status == KeyMatchStatus.error;

    // 錯誤狀態不顯示徽章
    if (isError) return const SizedBox.shrink();

    final Color color = isMatched ? AppColors.success : AppColors.error;
    final IconData icon = isMatched ? Icons.link : Icons.link_off;
    final String label = isMatched
        ? l10n.certViewKeyMatched
        : l10n.certViewKeyMismatched;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
              ),
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

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 64,
              color: AppColors.textHint.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.certViewNoCerts,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 憑證鏈節點卡片
// ============================================================

/// 憑證有效性狀態
enum _CertStatus { valid, expiring, expired, notYetValid }

class _CertChainTile extends StatelessWidget {
  final X509CertificateData cert;
  final int index;
  final int totalCount;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CertChainTile({
    required this.cert,
    required this.index,
    required this.totalCount,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = _getStatus();
    final subjectCN = CertificateService.getSubjectCN(cert);
    final issuerCN = CertificateService.getIssuerCN(cert);
    final isSelfSigned = CertificateService.isSelfSigned(cert);
    final category = _getCategory(l10n);

    final validFrom = cert.tbsCertificate?.validity.notBefore;
    final validTo = cert.tbsCertificate?.validity.notAfter;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isExpanded ? AppColors.primaryDark : AppColors.primaryDark.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: isExpanded
            ? [
                BoxShadow(
                  color: AppColors.glow,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // 標題列（可點擊展開）
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // 鏈結指示器
                  _ChainIndicator(
                    index: index,
                    totalCount: totalCount,
                  ),
                  const SizedBox(width: 10),

                  // 狀態指示燈
                  _StatusDot(status: status),
                  const SizedBox(width: 10),

                  // 主體資訊
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subjectCN,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // 類別標籤
                            _CategoryBadge(label: category.label, color: category.color),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isSelfSigned
                                    ? l10n.certViewSelfSigned
                                    : '${l10n.certViewIssuer}: $issuerCN',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 有效期限
                  if (validFrom != null && validTo != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ValidityBadge(status: status, from: validFrom, to: validTo),
                    ),

                  // 展開/折疊圖示
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 詳細資訊（展開時）
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _CertDetailCard(cert: cert),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  _CertStatus _getStatus() {
    final validFrom = cert.tbsCertificate?.validity.notBefore;
    final validTo = cert.tbsCertificate?.validity.notAfter;
    if (validFrom == null || validTo == null) return _CertStatus.valid;

    final now = DateTime.now();
    if (now.isBefore(validFrom)) return _CertStatus.notYetValid;
    if (now.isAfter(validTo)) return _CertStatus.expired;

    // 如果 30 天內到期，視為即將過期
    if (now.isAfter(validTo.subtract(const Duration(days: 30)))) {
      return _CertStatus.expiring;
    }

    return _CertStatus.valid;
  }

  _CategoryResult _getCategory(AppLocalizations l10n) {
    final isSelfSigned = CertificateService.isSelfSigned(cert);

    if (totalCount == 1) {
      if (isSelfSigned) {
        return _CategoryResult(
          label: l10n.certViewRootCA,
          color: AppColors.warning,
        );
      }
      return _CategoryResult(
        label: l10n.certViewEndEntity,
        color: AppColors.accent,
      );
    }

    if (index == 0) {
      return _CategoryResult(
        label: l10n.certViewEndEntity,
        color: AppColors.accent,
      );
    }

    if (index == totalCount - 1) {
      return _CategoryResult(
        label: l10n.certViewRootCA,
        color: AppColors.warning,
      );
    }

    return _CategoryResult(
      label: l10n.certViewIntermediateCA,
      color: AppColors.primaryLight,
    );
  }
}

/// 類別標籤結果
class _CategoryResult {
  final String label;
  final Color color;
  const _CategoryResult({required this.label, required this.color});
}

// ============================================================
// 類別標籤元件
// ============================================================

class _CategoryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CategoryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ============================================================
// 鏈結指示器
// ============================================================

class _ChainIndicator extends StatelessWidget {
  final int index;
  final int totalCount;

  const _ChainIndicator({required this.index, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final isFirst = index == 0;
    final isLast = index == totalCount - 1;
    final isEndEntity = isFirst && totalCount > 1;
    final isRoot = isLast && totalCount > 1;

    return SizedBox(
      width: 32,
      height: 48,
      child: CustomPaint(
        painter: _ChainLinePainter(
          isFirst: isFirst,
          isLast: isLast,
          isEndEntity: isEndEntity,
          isRoot: isRoot,
          single: totalCount == 1,
        ),
      ),
    );
  }
}

class _ChainLinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final bool isEndEntity;
  final bool isRoot;
  final bool single;

  _ChainLinePainter({
    required this.isFirst,
    required this.isLast,
    required this.isEndEntity,
    required this.isRoot,
    required this.single,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryDark
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final dotRadius = 4.0;
    final dotPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    if (single) {
      // 單一憑證：只畫一個點
      canvas.drawCircle(Offset(centerX, centerY), 3.0, dotPaint);
      return;
    }

    if (isFirst) {
      // 頂端憑證：從點向下畫線到底部
      canvas.drawLine(
        Offset(centerX, centerY + dotRadius),
        Offset(centerX, size.height),
        paint,
      );
      canvas.drawCircle(Offset(centerX, centerY), dotRadius, dotPaint);
    } else if (isLast) {
      // 底部（根）憑證：從頂部畫線到點
      canvas.drawLine(
        Offset(centerX, 0),
        Offset(centerX, centerY - dotRadius),
        paint,
      );
      canvas.drawCircle(Offset(centerX, centerY), dotRadius, dotPaint);
    } else {
      // 中間憑證：從頂到點，從點到底
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), paint);
      canvas.drawCircle(Offset(centerX, centerY), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChainLinePainter oldDelegate) => false;
}

// ============================================================
// 狀態指示燈
// ============================================================

class _StatusDot extends StatelessWidget {
  final _CertStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _CertStatus.valid => AppColors.success,
      _CertStatus.expiring => AppColors.warning,
      _CertStatus.expired => AppColors.error,
      _CertStatus.notYetValid => AppColors.textHint,
    };

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 有效期限標籤
// ============================================================

class _ValidityBadge extends StatelessWidget {
  final _CertStatus status;
  final DateTime from;
  final DateTime to;

  const _ValidityBadge({
    required this.status,
    required this.from,
    required this.to,
  });

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (status) {
      _CertStatus.valid => l10n.certViewValid,
      _CertStatus.expiring => l10n.certViewValid,
      _CertStatus.expired => l10n.certViewExpired,
      _CertStatus.notYetValid => l10n.certViewNotYetValid,
    };

    final color = switch (status) {
      _CertStatus.valid => AppColors.success,
      _CertStatus.expiring => AppColors.warning,
      _CertStatus.expired => AppColors.error,
      _CertStatus.notYetValid => AppColors.textHint,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: color, fontSize: 10),
        ),
        const SizedBox(width: 4),
        Text(
          '${_formatDate(from)} ~ ${_formatDate(to)}',
          style: const TextStyle(color: AppColors.textHint, fontSize: 10),
        ),
      ],
    );
  }
}

// ============================================================
// 憑證詳細資訊卡片
// ============================================================

class _CertDetailCard extends StatelessWidget {
  final X509CertificateData cert;

  const _CertDetailCard({required this.cert});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: AppColors.primaryDark),
          const SizedBox(height: 10),

          // 主體 & 簽發者
          _buildSubjectIssuerSection(l10n),
          const SizedBox(height: 12),

          // 有效期限
          _buildValiditySection(l10n),
          const SizedBox(height: 12),

          // 序號 & 版本 & 簽名演算法
          _buildMetaSection(l10n),
          const SizedBox(height: 12),

          // 公開金鑰
          _buildPublicKeySection(l10n),
          const SizedBox(height: 12),

          // 指紋
          _buildThumbprintSection(l10n),
          const SizedBox(height: 12),

          // 主體別名
          _buildSANSection(l10n),
          const SizedBox(height: 12),

          // 金鑰用途
          _buildKeyUsageSection(l10n),
          const SizedBox(height: 12),

          // 基本約束
          _buildBasicConstraintsSection(l10n),

          // PEM 文字
          if (cert.plain != null) ...[
            const SizedBox(height: 12),
            _buildPemSection(context, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectIssuerSection(AppLocalizations l10n) {
    return _DetailBlock(
      children: [
        _DetailRow(
          label: l10n.certViewSubject,
          value: CertificateService.dnToString(cert.tbsCertificate?.subject),
          mono: true,
        ),
        const SizedBox(height: 4),
        _DetailRow(
          label: l10n.certViewIssuer,
          value: CertificateService.dnToString(cert.tbsCertificate?.issuer),
          mono: true,
        ),
      ],
    );
  }

  Widget _buildValiditySection(AppLocalizations l10n) {
    final v = cert.tbsCertificate?.validity;
    if (v == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final isExpired = now.isAfter(v.notAfter);
    final isNotYet = now.isBefore(v.notBefore);

    String formatDt(DateTime d) {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    }

    final statusColor = isExpired
        ? AppColors.error
        : isNotYet
            ? AppColors.textHint
            : AppColors.success;

    return _DetailBlock(
      children: [
        _DetailRow(
          label: l10n.certViewNotBefore,
          value: formatDt(v.notBefore),
          mono: true,
        ),
        const SizedBox(height: 4),
        _DetailRow(
          label: l10n.certViewNotAfter,
          value: formatDt(v.notAfter),
          mono: true,
          valueColor: statusColor,
        ),
      ],
    );
  }

  Widget _buildMetaSection(AppLocalizations l10n) {
    final ver = cert.tbsCertificate?.version;
    return _DetailBlock(
      children: [
        _DetailRow(
          label: l10n.certViewSerialNumber,
          value: cert.tbsCertificate?.serialNumber.toRadixString(16).toUpperCase() ?? '',
          mono: true,
        ),
        const SizedBox(height: 4),
        _DetailRow(
          label: l10n.certViewSignatureAlgorithm,
          value: cert.tbsCertificate?.signatureAlgorithmReadableName ?? '',
          mono: true,
        ),
        if (ver != null) ...[
          const SizedBox(height: 4),
          _DetailRow(
            label: l10n.certViewVersion,
            value: 'v$ver',
          ),
        ],
      ],
    );
  }

  Widget _buildPublicKeySection(AppLocalizations l10n) {
    final spki = cert.tbsCertificate?.subjectPublicKeyInfo;
    if (spki == null) return const SizedBox.shrink();

    final items = <Widget>[];

    if (spki.algorithmReadableName != null) {
      items.add(_DetailRow(
        label: l10n.certViewAlgorithm,
        value: spki.algorithmReadableName!,
      ));
    }

    if (spki.length != null) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 4));
      items.add(_DetailRow(
        label: l10n.certViewKeySize,
        value: l10n.bitsSuffix(spki.length!),
      ));
    }

    if (spki.parameterReadableName != null) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 4));
      items.add(_DetailRow(
        label: l10n.certViewCurve,
        value: spki.parameterReadableName!,
      ));
    }

    if (spki.exponent != null) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 4));
      items.add(_DetailRow(
        label: l10n.certViewExponent,
        value: spki.exponent.toString(),
      ));
    }

    if (spki.sha256Thumbprint != null) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 4));
      items.add(_DetailRow(
        label: '${l10n.certViewThumbprint} (${l10n.certViewSHA256})',
        value: _formatHex(spki.sha256Thumbprint!),
        mono: true,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _DetailBlock(children: items);
  }

  Widget _buildThumbprintSection(AppLocalizations l10n) {
    return _DetailBlock(
      children: [
        if (cert.sha1Thumbprint != null)
          _DetailRow(
            label: l10n.certViewSHA1,
            value: _formatHex(cert.sha1Thumbprint!),
            mono: true,
          ),
        if (cert.sha1Thumbprint != null && cert.sha256Thumbprint != null)
          const SizedBox(height: 4),
        if (cert.sha256Thumbprint != null)
          _DetailRow(
            label: l10n.certViewSHA256,
            value: _formatHex(cert.sha256Thumbprint!),
            mono: true,
          ),
        if (cert.md5Thumbprint != null &&
            (cert.sha1Thumbprint != null || cert.sha256Thumbprint != null))
          const SizedBox(height: 4),
        if (cert.md5Thumbprint != null)
          _DetailRow(
            label: l10n.certViewMD5,
            value: _formatHex(cert.md5Thumbprint!),
            mono: true,
          ),
      ],
    );
  }

  Widget _buildSANSection(AppLocalizations l10n) {
    final ext = cert.tbsCertificate?.extensions;
    final sans = ext?.subjectAlternativNames;
    final allSans = sans?.toList() ?? <String>[];

    if (allSans.isEmpty) return const SizedBox.shrink();

    return _DetailBlock(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                l10n.certViewSubjectAltName,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: allSans.map((san) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      san,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyUsageSection(AppLocalizations l10n) {
    final ext = cert.tbsCertificate?.extensions;
    final keyUsage = ext?.keyUsage;
    final extKeyUsage = ext?.extKeyUsage;

    if ((keyUsage == null || keyUsage.isEmpty) &&
        (extKeyUsage == null || extKeyUsage.isEmpty)) {
      return const SizedBox.shrink();
    }

    final items = <Widget>[];

    if (keyUsage != null && keyUsage.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            l10n.certViewKeyUsage,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
            ),
          ),
        ),
      );
      for (final usage in keyUsage) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 1),
            child: Row(
              children: [
                const Icon(Icons.check, size: 14, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  CertificateService.keyUsageToString(usage),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (extKeyUsage != null && extKeyUsage.isNotEmpty) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 4));
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            l10n.certViewExtendedKeyUsage,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
            ),
          ),
        ),
      );
      for (final usage in extKeyUsage) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 1),
            child: Row(
              children: [
                const Icon(Icons.check, size: 14, color: AppColors.accent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    CertificateService.extKeyUsageToString(usage),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return _DetailBlock(children: items);
  }

  Widget _buildBasicConstraintsSection(AppLocalizations l10n) {
    final ext = cert.tbsCertificate?.extensions;
    final ca = ext?.cA;
    final pathLen = ext?.pathLenConstraint;

    if (ca == null && pathLen == null) return const SizedBox.shrink();

    return _DetailBlock(
      children: [
        if (ca != null)
          _DetailRow(
            label: l10n.certViewCA,
            value: ca ? l10n.boolYes : l10n.boolNo,
            valueColor: ca ? AppColors.warning : AppColors.textSecondary,
          ),
        if (ca != null && pathLen != null) const SizedBox(height: 4),
        if (pathLen != null)
          _DetailRow(
            label: l10n.certViewPathLenConstraint,
            value: pathLen < 0 ? l10n.noneValue : pathLen.toString(),
          ),
      ],
    );
  }

  Widget _buildPemSection(BuildContext context, AppLocalizations l10n) {
    return _DetailBlock(
      children: [
        Row(
          children: [
            Text(
              l10n.certViewPemText,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: cert.plain!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.certViewCopied),
                    duration: const Duration(seconds: 1),
                    backgroundColor: AppColors.surface,
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    l10n.certViewCopyPem,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.primaryDark.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: SelectableText(
              cert.plain!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatHex(String hex) {
    return _fmtHex(hex);
  }
}

/// 格式化十六進位字串（插入空格分組）
String _fmtHex(String hex) {
  if (hex.length <= 16) return hex;
  final buf = StringBuffer();
  for (var i = 0; i < hex.length; i += 2) {
    if (i > 0) {
      buf.write(i % 16 == 0 ? '\n' : ' ');
    }
    if (i + 2 <= hex.length) {
      buf.write(hex.substring(i, i + 2));
    } else {
      buf.write(hex.substring(i));
    }
  }
  return buf.toString();
}

// ============================================================
// 共用輔助元件
// ============================================================

/// 操作按鈕
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.primary = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = primary ? AppColors.primary : AppColors.surfaceLight;
    final fgColor = primary ? AppColors.textPrimary : AppColors.textSecondary;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fgColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 12,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 詳細資訊區塊容器
class _DetailBlock extends StatelessWidget {
  final List<Widget> children;

  const _DetailBlock({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// 詳細資訊行（標籤-值配對）
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
