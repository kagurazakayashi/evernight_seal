import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/certificate_service.dart';
import '../theme/app_colors.dart';

/// 建立憑證請求（CSR）畫面
///
/// 提供使用者設定主體 DN、金鑰、簽名演算法、SAN 等選項，
/// 產生 PKCS#10 憑證簽名請求（PEM 格式）。
class CreateCSRScreen extends StatefulWidget {
  /// 從建立私鑰畫面傳遞過來的已產生私鑰 PEM（可為 null）
  final String? lastGeneratedKeyPem;

  /// 查看詳細資訊的回呼，傳入 PEM 文字後導覽到憑證檢視畫面
  final ValueChanged<String>? onViewDetails;

  /// 當 CSR 產生成功時回呼，傳出 CSR PEM 文字
  final ValueChanged<String>? onCSRGenerated;

  const CreateCSRScreen({
    super.key,
    this.lastGeneratedKeyPem,
    this.onViewDetails,
    this.onCSRGenerated,
  });

  @override
  State<CreateCSRScreen> createState() => _CreateCSRScreenState();
}

/// SAN 條目模型
class _SANEntry {
  String type; // 'DNS' or 'IP'
  final TextEditingController controller;

  _SANEntry({this.type = 'DNS', String value = ''})
      : controller = TextEditingController(text: value);

  void dispose() {
    controller.dispose();
  }
}

class _CreateCSRScreenState extends State<CreateCSRScreen> {
  // ── 載入的私鑰 ──
  String? _privateKeyPem;
  String? _detectedKeyType; // 'RSA' or 'EC'
  int? _detectedKeySize;
  String? _detectedCurve;

  /// 建立私鑰畫面是否有已產生的私鑰可用
  bool get _hasLastGeneratedKey {
    return widget.lastGeneratedKeyPem != null &&
        widget.lastGeneratedKeyPem!.isNotEmpty;
  }

  // ── 主體 DN 控制器 ──
  final _cnController = TextEditingController();
  final _oController = TextEditingController();
  final _ouController = TextEditingController();
  final _lController = TextEditingController();
  final _stController = TextEditingController();
  final _cController = TextEditingController();

  // ── 簽名選項 ──
  String _signatureAlgorithm = 'SHA-256';

  // ── SAN ──
  final List<_SANEntry> _sanEntries = [];

  // ── 偏好持久化 ──
  SharedPreferences? _prefs;

  // ── 結果狀態 ──
  String? _csrPem;
  String? _errorMessage;
  bool _isGenerating = false;

  // ── SharedPreferences key 常數 ──
  static const _prefCN = 'csr_cn';
  static const _prefO = 'csr_o';
  static const _prefOU = 'csr_ou';
  static const _prefL = 'csr_l';
  static const _prefST = 'csr_st';
  static const _prefC = 'csr_c';
  static const _prefSigAlgo = 'csr_signatureAlgo';
  static const _prefSANs = 'csr_sans';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _cnController.dispose();
    _oController.dispose();
    _ouController.dispose();
    _lController.dispose();
    _stController.dispose();
    _cController.dispose();
    for (final entry in _sanEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    setState(() {
      _cnController.text = prefs.getString(_prefCN) ?? '';
      _oController.text = prefs.getString(_prefO) ?? '';
      _ouController.text = prefs.getString(_prefOU) ?? '';
      _lController.text = prefs.getString(_prefL) ?? '';
      _stController.text = prefs.getString(_prefST) ?? '';
      _cController.text = prefs.getString(_prefC) ?? '';
      _signatureAlgorithm = prefs.getString(_prefSigAlgo) ?? 'SHA-256';

      // 還原 SAN
      final sanStr = prefs.getString(_prefSANs);
      if (sanStr != null && sanStr.isNotEmpty) {
        for (final entry in sanStr.split('|')) {
          final parts = entry.split(':');
          if (parts.length >= 2) {
            final type = parts[0];
            final value = parts.sublist(1).join(':');
            _sanEntries.add(_SANEntry(type: type, value: value));
          }
        }
      }
    });

    debugPrint(
      '[CreateCSRScreen] 載入偏好: hasKey=${_privateKeyPem != null}, '
      'cn=${_cnController.text}, sigAlgo=$_signatureAlgorithm',
    );
  }

  Future<void> _savePreferences() async {
    final prefs = _prefs;
    if (prefs == null) return;

    await prefs.setString(_prefCN, _cnController.text);
    await prefs.setString(_prefO, _oController.text);
    await prefs.setString(_prefOU, _ouController.text);
    await prefs.setString(_prefL, _lController.text);
    await prefs.setString(_prefST, _stController.text);
    await prefs.setString(_prefC, _cController.text);
    await prefs.setString(_prefSigAlgo, _signatureAlgorithm);
    await prefs.setString(
      _prefSANs,
      _sanEntries
          .where((e) => e.controller.text.isNotEmpty)
          .map((e) => '${e.type}:${e.controller.text}')
          .join('|'),
    );

    debugPrint('[CreateCSRScreen] 已儲存偏好');
  }

  /// 解析已載入的私鑰以偵測類型/大小/曲線
  void _detectKeyInfo() {
    if (_privateKeyPem == null) {
      _detectedKeyType = null;
      _detectedKeySize = null;
      _detectedCurve = null;
      return;
    }
    try {
      final info = CertificateService.parsePrivateKeyPem(_privateKeyPem!);
      if (info != null) {
        _detectedKeyType = info.algorithm;
        _detectedKeySize = info.keySize;
        _detectedCurve = info.curveName;
      }
    } catch (_) {
      _detectedKeyType = 'Unknown';
    }
  }

  /// 載入私鑰（貼上 PEM 文字）
  void _loadKeyFromPem(String pem) {
    debugPrint('[CreateCSRScreen] 載入私鑰 PEM: ${pem.length} 字元');
    setState(() {
      _privateKeyPem = pem;
      _detectKeyInfo();
    });
    _savePreferences();
  }

  /// 從檔案載入私鑰
  Future<void> _loadKeyFromFile() async {
    debugPrint('[CreateCSRScreen] 開啟私鑰檔案');
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open Private Key File',
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      // 嘗試解碼為 UTF-8
      String pem;
      try {
        pem = utf8.decode(bytes);
      } catch (_) {
        setState(() => _errorMessage = 'Failed to read file as text');
        return;
      }

      // 檢查是否包含私鑰標頭
      if (!CertificateService.hasPrivateKeyPem(pem)) {
        setState(
            () => _errorMessage = 'No valid private key found in the file');
        return;
      }

      _loadKeyFromPem(pem);
    } catch (e) {
      debugPrint('[CreateCSRScreen] 載入檔案失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  /// 清除已載入的私鑰
  void _clearKey() {
    debugPrint('[CreateCSRScreen] 清除私鑰');
    setState(() {
      _privateKeyPem = null;
      _detectedKeyType = null;
      _detectedKeySize = null;
      _detectedCurve = null;
    });
    _savePreferences();
  }

  /// 使用剛建立的私鑰（從 HomeScreen 傳遞的值讀取）
  void _useLastGeneratedKey() {
    debugPrint('[CreateCSRScreen] 載入剛剛建立的私鑰');
    final pem = widget.lastGeneratedKeyPem;
    if (pem != null && pem.isNotEmpty) {
      _loadKeyFromPem(pem);
      debugPrint('[CreateCSRScreen] 已載入剛剛建立的私鑰');
    }
  }

  // ── 產生 CSR ──

  void _generateCSR() {
    debugPrint(
      '[CreateCSRScreen] 產生 CSR: cn=${_cnController.text}, '
      'sigAlgo=$_signatureAlgorithm',
    );

    // 驗證 CN 必填
    final cn = _cnController.text.trim();
    if (cn.isEmpty) {
      setState(() => _errorMessage = 'Common Name (CN) is required');
      return;
    }

    // 驗證私鑰已載入
    if (_privateKeyPem == null || _detectedKeyType == null) {
      final l10n = AppLocalizations.of(context);
      setState(() => _errorMessage = l10n.csrKeyRequired);
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _csrPem = null;
    });

    try {
      // 1. 解析私鑰並推導公鑰
      final String keyType = _detectedKeyType!;
      final PrivateKey privateKey;
      final PublicKey publicKey;

      if (keyType == 'RSA' || keyType == 'RSA_PKCS1') {
        final rsaPriv = keyType == 'RSA_PKCS1'
            ? CryptoUtils.rsaPrivateKeyFromPemPkcs1(_privateKeyPem!)
            : CryptoUtils.rsaPrivateKeyFromPem(_privateKeyPem!);
        privateKey = rsaPriv;
        publicKey = RSAPublicKey(rsaPriv.n!, BigInt.from(65537));
      } else if (keyType == 'EC' || keyType == 'ECC') {
        final ecPriv = CryptoUtils.ecPrivateKeyFromPem(_privateKeyPem!);
        privateKey = ecPriv;
        // 從私鑰推導公鑰點 Q = d * G
        final G = ecPriv.parameters!.G;
        final Q = G * ecPriv.d!;
        publicKey = ECPublicKey(Q, ecPriv.parameters!);
      } else {
        setState(() {
          _errorMessage = 'Unsupported key type: $keyType';
          _isGenerating = false;
        });
        return;
      }

      // 2. 建立主體 DN 屬性（必須使用大寫名稱，ASN1ObjectIdentifier.fromName 只認大寫）
      final attributes = <String, String>{'CN': cn};
      void addAttr(String key, TextEditingController ctrl) {
        final v = ctrl.text.trim();
        if (v.isNotEmpty) attributes[key] = v;
      }

      addAttr('O', _oController);
      addAttr('OU', _ouController);
      addAttr('L', _lController);
      addAttr('ST', _stController);
      addAttr('C', _cController);

      // 3. 產生 CSR PEM
      final String csrPem;
      if (keyType == 'RSA' || keyType == 'RSA_PKCS1') {
        csrPem = X509Utils.generateRsaCsrPem(
          attributes,
          privateKey as RSAPrivateKey,
          publicKey as RSAPublicKey,
          signingAlgorithm: _signatureAlgorithm,
          san: _getSANList(),
        );
      } else {
        csrPem = X509Utils.generateEccCsrPem(
          attributes,
          privateKey as ECPrivateKey,
          publicKey as ECPublicKey,
          signingAlgorithm: _signatureAlgorithm,
          san: _getSANList(),
        );
      }

      setState(() {
        _csrPem = csrPem;
        _isGenerating = false;
      });

      debugPrint('[CreateCSRScreen] CSR 產生成功');
      widget.onCSRGenerated?.call(csrPem);
    } catch (e) {
      debugPrint('[CreateCSRScreen] CSR 產生失敗: $e');
      setState(() {
        _errorMessage = e.toString();
        _isGenerating = false;
      });
    }
  }

  /// 取得非空的 SAN 列表
  List<String>? _getSANList() {
    final sans = _sanEntries
        .map((e) => e.controller.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return sans.isNotEmpty ? sans : null;
  }

  // ── 操作輔助 ──

  void _copyPem(String pem) {
    Clipboard.setData(ClipboardData(text: pem));
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.certViewCopied),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.surface,
      ),
    );
    debugPrint('[CreateCSRScreen] 已複製到剪貼簿');
  }

  Future<void> _savePem(String pem, String defaultName) async {
    debugPrint('[CreateCSRScreen] 儲存檔案: $defaultName');

    try {
      final bytes = utf8.encode(pem);
      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save File',
        fileName: defaultName,
        type: FileType.any,
        bytes: bytes,
      );

      if (outputPath != null && outputPath.isNotEmpty) {
        debugPrint('[CreateCSRScreen] 檔案已儲存至: $outputPath');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to: $outputPath'),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.surface,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CreateCSRScreen] 儲存失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _clearResult() {
    debugPrint('[CreateCSRScreen] 清除結果');
    setState(() {
      _csrPem = null;
      _errorMessage = null;
    });
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuCreateCSR),
        actions: [
          if (_csrPem != null)
            IconButton(
              icon: const Icon(Icons.clear_all_outlined),
              tooltip: l10n.certViewClear,
              onPressed: _clearResult,
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
                  _buildSectionHeader(l10n.selfCASectionKey),
                  const SizedBox(height: 8),
                  _buildPrivateKeySection(l10n),

                  const SizedBox(height: 16),
                  _buildSubjectDNHeader(l10n),
                  const SizedBox(height: 8),
                  _buildSubjectDN(l10n),

                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.csrSectionSignature),
                  const SizedBox(height: 8),
                  _buildSignatureSelector(l10n),

                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.selfCASectionExtensions),
                  const SizedBox(height: 8),
                  _buildSANSection(l10n),

                  const SizedBox(height: 16),
                  _buildGenerateButton(l10n),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(l10n),
                  ],
                  if (_csrPem != null) ...[
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

  /// 區塊標題
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

  /// 主題 DN 區段標題（含「從 CA 複製」按鈕）
  Widget _buildSubjectDNHeader(AppLocalizations l10n) {
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
            l10n.selfCASectionSubject,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          _SmallOutlineButton(
            icon: Icons.content_copy_outlined,
            label: l10n.copyDNFromCA,
            onPressed: _copyDNFromCA,
          ),
        ],
      ),
    );
  }

  /// 從自簽名 CA 畫面的 SharedPreferences 複製主題 DN 欄位
  void _copyDNFromCA() {
    final prefs = _prefs;
    if (prefs == null) return;
    debugPrint('[CreateCSRScreen] 從 CA 複製主題 DN');
    setState(() {
      _cnController.text = prefs.getString('selfCA_cn') ?? '';
      _oController.text = prefs.getString('selfCA_o') ?? '';
      _ouController.text = prefs.getString('selfCA_ou') ?? '';
      _lController.text = prefs.getString('selfCA_l') ?? '';
      _stController.text = prefs.getString('selfCA_st') ?? '';
      _cController.text = prefs.getString('selfCA_c') ?? '';
    });
    _savePreferences();
  }

  /// 小標籤（欄位標題）
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

  // ── 私鑰載入區塊 ──

  Widget _buildPrivateKeySection(AppLocalizations l10n) {
    final hasKey = _privateKeyPem != null && _detectedKeyType != null;

    if (hasKey) {
      // 已載入金鑰：顯示金鑰資訊與操作
      final typeStr = _detectedKeyType;
      String desc = typeStr ?? 'Unknown';
      if (_detectedKeySize != null) {
        desc += ' $_detectedKeySize bits';
      }
      if (_detectedCurve != null) {
        desc += ' ($_detectedCurve)';
      }

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.selfCAKeyLoaded,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
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

    // 尚未載入金鑰：顯示輸入區域
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFieldLabel(l10n.selfCAPrivateKey, required: true),
            ),
            if (_hasLastGeneratedKey)
              _AccentButton(
                icon: Icons.swap_horiz_outlined,
                label: l10n.selfCAUseLastKey,
                onPressed: () => _useLastGeneratedKey(),
              )
            else
              Opacity(
                opacity: 0.4,
                child: _SmallOutlineButton(
                  icon: Icons.swap_horiz_outlined,
                  label: l10n.selfCAUseLastKey,
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
          height: 80,
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

  // ── 主體 DN 輸入區 ──

  Widget _buildSubjectDN(AppLocalizations l10n) {
    return Column(
      children: [
        _buildTextField(
          controller: _cnController,
          label: l10n.selfCACommonName,
          hint: l10n.csrCommonNameHint,
          required: true,
          onChanged: (_) => _savePreferences(),
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _oController,
          label: l10n.selfCAOrganization,
          hint: l10n.selfCAOrganizationHint,
          onChanged: (_) => _savePreferences(),
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _ouController,
          label: l10n.selfCAOrgUnit,
          hint: l10n.selfCAOrgUnitHint,
          onChanged: (_) => _savePreferences(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _lController,
                label: l10n.selfCALocality,
                hint: l10n.selfCALocalityHint,
                onChanged: (_) => _savePreferences(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTextField(
                controller: _stController,
                label: l10n.selfCAState,
                hint: l10n.selfCAStateHint,
                onChanged: (_) => _savePreferences(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _cController,
          label: l10n.selfCACountry,
          hint: l10n.selfCACountryHint,
          maxLength: 2,
          onChanged: (_) => _savePreferences(),
        ),
      ],
    );
  }

  // ── 簽名演算法 ──

  Widget _buildSignatureSelector(AppLocalizations l10n) {
    const sigAlgos = ['SHA-256', 'SHA-384', 'SHA-512'];

    return _buildDropdownSelector<String>(
      label: l10n.selfCASignatureAlgorithm,
      value: _signatureAlgorithm,
      items: sigAlgos,
      itemLabel: (v) => v,
      onChanged: (v) {
        debugPrint('[CreateCSRScreen] 選擇簽名演算法: $v');
        setState(() => _signatureAlgorithm = v);
        _savePreferences();
      },
    );
  }

  // ── SAN ──

  Widget _buildSANSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(l10n.selfCASANManage),
        const SizedBox(height: 4),
        ..._sanEntries.asMap().entries.map((e) {
          final idx = e.key;
          final entry = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                // 類型下拉
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.primaryDark.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: entry.type,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.textHint,
                        size: 18,
                      ),
                      items: ['DNS', 'IP'].map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(
                            t == 'DNS'
                                ? l10n.selfCASANTypeDNS
                                : l10n.selfCASANTypeIP,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => entry.type = v);
                          _savePreferences();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 文字輸入
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: entry.controller,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.selfCASANPlaceholder,
                        hintStyle: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
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
                      onChanged: (_) => _savePreferences(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 刪除按鈕
                _IconButton(
                  icon: Icons.remove_circle_outline,
                  color: AppColors.textHint,
                  size: 20,
                  onTap: () {
                    debugPrint('[CreateCSRScreen] 刪除 SAN #$idx');
                    entry.dispose();
                    setState(() => _sanEntries.removeAt(idx));
                    _savePreferences();
                  },
                ),
              ],
            ),
          );
        }),
        // 新增 SAN 按鈕
        _SmallOutlineButton(
          icon: Icons.add_outlined,
          label: l10n.selfCASANAdd,
          onPressed: () {
            debugPrint('[CreateCSRScreen] 新增 SAN');
            setState(() => _sanEntries.add(_SANEntry()));
            _savePreferences();
          },
        ),
      ],
    );
  }

  // ── 產生按鈕 ──

  Widget _buildGenerateButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _isGenerating ? null : _generateCSR,
        icon: _isGenerating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              )
            : const Icon(Icons.description_outlined, size: 20),
        label: Text(
          _isGenerating ? 'Generating...' : l10n.csrGenerate,
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
    final csrPem = _csrPem!;
    final defaultFileName =
        'csr_${_cnController.text.trim()}_${_detectedKeyType ?? "key"}.pem';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題列
        Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              l10n.csrResultTitle,
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

        // PEM 文字區塊
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 240),
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
              csrPem,
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

        // 操作按鈕列
        Row(
          children: [
            _ActionChip(
              icon: Icons.copy_outlined,
              label: l10n.csrCopyPem,
              onPressed: () => _copyPem(csrPem),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.save_outlined,
              label: l10n.csrSavePem,
              onPressed: () => _savePem(csrPem, defaultFileName),
            ),
            if (widget.onViewDetails != null) ...[
              const Spacer(),
              _ActionChip(
                icon: Icons.visibility_outlined,
                label: l10n.selfCAViewDetails,
                onPressed: () => widget.onViewDetails!(csrPem),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── 泛用元件 ──

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    ValueChanged<String>? onChanged,
    TextInputType inputType = TextInputType.text,
    int? maxLength,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label, required: required),
        SizedBox(
          height: 38,
          child: TextField(
            controller: controller,
            keyboardType: inputType,
            maxLength: maxLength,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              counterText: '',
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
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownSelector<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.primaryDark.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.textHint,
              ),
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemLabel(item),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 共用私有元件
// ============================================================

/// 小型強調按鈕（同主按鈕配色，用於可用狀態）
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

/// 操作按鈕（小型）
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

/// 小型圖示按鈕
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

/// 小型外框按鈕
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
