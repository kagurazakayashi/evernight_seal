import 'dart:convert';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/certificate_service.dart';
import '../theme/app_colors.dart';
import '../widgets/validity_input.dart';

/// 使用 CA 簽發憑證畫面
///
/// 載入 CA 憑證、CA 私鑰、CSR，設定有效期與擴展後，
/// 產生 CA 簽章的終端實體（或中間 CA）憑證。
class IssueCertScreen extends StatefulWidget {
  /// 從建立私鑰畫面傳遞過來的已產生私鑰 PEM
  final String? lastGeneratedKeyPem;

  /// 從自簽名 CA 畫面傳遞過來的已產生 CA 憑證 PEM
  final String? lastGeneratedCACertPem;

  /// 從建立 CSR 畫面傳遞過來的已產生 CSR PEM
  final String? lastGeneratedCSRPem;

  /// 查看詳細資訊的回呼
  final ValueChanged<String>? onViewDetails;

  const IssueCertScreen({
    super.key,
    this.lastGeneratedKeyPem,
    this.lastGeneratedCACertPem,
    this.lastGeneratedCSRPem,
    this.onViewDetails,
  });

  @override
  State<IssueCertScreen> createState() => _IssueCertScreenState();
}

/// SAN 條目模型
class _SANEntry {
  String type;
  final TextEditingController controller;

  _SANEntry({this.type = 'DNS', String value = ''})
      : controller = TextEditingController(text: value);

  void dispose() {
    controller.dispose();
  }
}

class _IssueCertScreenState extends State<IssueCertScreen> {
  // ── CA 憑證 ──
  String? _caCertPem;
  String? _caCertCN;

  // ── CA 私鑰 ──
  String? _caKeyPem;
  String? _detectedKeyType;
  int? _detectedKeySize;
  String? _detectedCurve;

  // ── CSR ──
  String? _csrPem;
  String? _csrSubjectCN;

  // ── 有效期與簽名選項 ──
  int _validityDays = 365;
  String _signatureAlgorithm = 'SHA-256';
  final _serialController = TextEditingController();

  // ── 擴展選項 ──
  final Set<KeyUsage> _keyUsageSet = {
    KeyUsage.DIGITAL_SIGNATURE,
    KeyUsage.KEY_ENCIPHERMENT,
  };
  final Set<ExtendedKeyUsage> _extKeyUsageSet = {};
  bool _isCA = false;
  final _pathLenController = TextEditingController();
  final List<_SANEntry> _sanEntries = [];

  // ── 偏好持久化 ──
  SharedPreferences? _prefs;

  // ── 結果狀態 ──
  String? _certPem;
  String? _errorMessage;
  bool _isGenerating = false;

  // ── SharedPreferences key 常數 ──
  static const _prefCACertPem = 'issueCert_caCertPem';
  static const _prefCAKeyPem = 'issueCert_caKeyPem';
  static const _prefCSRPem = 'issueCert_csrPem';
  static const _prefDays = 'issueCert_days';
  static const _prefSigAlgo = 'issueCert_signatureAlgo';
  static const _prefSerial = 'issueCert_serial';
  static const _prefKeyUsage = 'issueCert_keyUsage';
  static const _prefExtKeyUsage = 'issueCert_extKeyUsage';
  static const _prefIsCA = 'issueCert_isCA';
  static const _prefPathLen = 'issueCert_pathLen';
  static const _prefSANs = 'issueCert_sans';

  /// 檢查是否有外部傳入的值可用
  bool get _hasLastCACert =>
      widget.lastGeneratedCACertPem != null &&
      widget.lastGeneratedCACertPem!.isNotEmpty;
  bool get _hasLastKey =>
      widget.lastGeneratedKeyPem != null &&
      widget.lastGeneratedKeyPem!.isNotEmpty;
  bool get _hasLastCSR =>
      widget.lastGeneratedCSRPem != null &&
      widget.lastGeneratedCSRPem!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _serialController.dispose();
    _pathLenController.dispose();
    for (final entry in _sanEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    setState(() {
      final caCert = prefs.getString(_prefCACertPem);
      if (caCert != null && caCert.isNotEmpty) {
        _caCertPem = caCert;
        _parseCACertInfo();
      }

      final caKey = prefs.getString(_prefCAKeyPem);
      if (caKey != null && caKey.isNotEmpty) {
        _caKeyPem = caKey;
        _detectKeyInfo();
      }

      final csr = prefs.getString(_prefCSRPem);
      if (csr != null && csr.isNotEmpty) {
        _csrPem = csr;
        _parseCSRInfo();
      }

      _validityDays =
          (prefs.getInt(_prefDays) ?? 365).clamp(1, getMaxValidityDays());
      _signatureAlgorithm = prefs.getString(_prefSigAlgo) ?? 'SHA-256';
      _serialController.text = prefs.getString(_prefSerial) ?? '';
      _isCA = prefs.getBool(_prefIsCA) ?? false;
      _pathLenController.text = prefs.getString(_prefPathLen) ?? '';

      // 還原 KeyUsage
      final kuStr = prefs.getString(_prefKeyUsage);
      if (kuStr != null && kuStr.isNotEmpty) {
        _keyUsageSet.clear();
        for (final s in kuStr.split(',')) {
          final idx = int.tryParse(s);
          if (idx != null && idx >= 0 && idx < KeyUsage.values.length) {
            _keyUsageSet.add(KeyUsage.values[idx]);
          }
        }
      }

      // 還原 ExtendedKeyUsage
      final ekuStr = prefs.getString(_prefExtKeyUsage);
      if (ekuStr != null && ekuStr.isNotEmpty) {
        _extKeyUsageSet.clear();
        for (final s in ekuStr.split(',')) {
          final idx = int.tryParse(s);
          if (idx != null && idx >= 0 && idx < ExtendedKeyUsage.values.length) {
            _extKeyUsageSet.add(ExtendedKeyUsage.values[idx]);
          }
        }
      }

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
      '[IssueCertScreen] 載入偏好: hasCACert=${_caCertPem != null}, '
      'hasCAKey=${_caKeyPem != null}, hasCSR=${_csrPem != null}, '
      'days=$_validityDays, sigAlgo=$_signatureAlgorithm',
    );
  }

  Future<void> _savePreferences() async {
    final prefs = _prefs;
    if (prefs == null) return;

    Future<void> setOrRemove(String key, String? value) async {
      if (value != null && value.isNotEmpty) {
        await prefs.setString(key, value);
      } else {
        await prefs.remove(key);
      }
    }

    await setOrRemove(_prefCACertPem, _caCertPem);
    await setOrRemove(_prefCAKeyPem, _caKeyPem);
    await setOrRemove(_prefCSRPem, _csrPem);
    await prefs.setInt(_prefDays, _validityDays);
    await prefs.setString(_prefSigAlgo, _signatureAlgorithm);
    await prefs.setString(_prefSerial, _serialController.text);
    await prefs.setBool(_prefIsCA, _isCA);
    await prefs.setString(_prefPathLen, _pathLenController.text);
    await prefs.setString(
      _prefKeyUsage,
      _keyUsageSet.map((e) => e.index.toString()).join(','),
    );
    await prefs.setString(
      _prefExtKeyUsage,
      _extKeyUsageSet.map((e) => e.index.toString()).join(','),
    );
    await prefs.setString(
      _prefSANs,
      _sanEntries
          .where((e) => e.controller.text.isNotEmpty)
          .map((e) => '${e.type}:${e.controller.text}')
          .join('|'),
    );

    debugPrint('[IssueCertScreen] 已儲存偏好');
  }

  // ── CA 憑證解析 ──

  void _parseCACertInfo() {
    _caCertCN = null;
    if (_caCertPem == null) return;
    try {
      final cert = X509Utils.x509CertificateFromPem(_caCertPem!);
      _caCertCN = CertificateService.getSubjectCN(cert);
    } catch (_) {
      _caCertCN = 'Unknown';
    }
  }

  void _loadCACertFromPem(String pem) {
    debugPrint('[IssueCertScreen] 載入 CA 憑證 PEM: ${pem.length} 字元');
    setState(() {
      _caCertPem = pem;
      _parseCACertInfo();
    });
    _savePreferences();
  }

  Future<void> _loadCACertFromFile() async {
    debugPrint('[IssueCertScreen] 開啟 CA 憑證檔案');
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open CA Certificate File',
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
        setState(() => _errorMessage = 'Failed to read file as text');
        return;
      }

      if (!pem.contains('BEGIN CERTIFICATE')) {
        setState(() => _errorMessage = 'No valid certificate found in the file');
        return;
      }

      _loadCACertFromPem(pem);
    } catch (e) {
      debugPrint('[IssueCertScreen] 載入 CA 憑證失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  void _clearCACert() {
    debugPrint('[IssueCertScreen] 清除 CA 憑證');
    setState(() {
      _caCertPem = null;
      _caCertCN = null;
    });
    _savePreferences();
  }

  void _useLastCACert() {
    debugPrint('[IssueCertScreen] 載入剛剛建立的 CA 憑證');
    final pem = widget.lastGeneratedCACertPem;
    if (pem != null && pem.isNotEmpty) {
      _loadCACertFromPem(pem);
    }
  }

  // ── CA 私鑰解析 ──

  void _detectKeyInfo() {
    if (_caKeyPem == null) {
      _detectedKeyType = null;
      _detectedKeySize = null;
      _detectedCurve = null;
      return;
    }
    try {
      final info = CertificateService.parsePrivateKeyPem(_caKeyPem!);
      if (info != null) {
        _detectedKeyType = info.algorithm;
        _detectedKeySize = info.keySize;
        _detectedCurve = info.curveName;
      }
    } catch (_) {
      _detectedKeyType = 'Unknown';
    }
  }

  void _loadCAKeyFromPem(String pem) {
    debugPrint('[IssueCertScreen] 載入 CA 私鑰 PEM: ${pem.length} 字元');
    setState(() {
      _caKeyPem = pem;
      _detectKeyInfo();
    });
    _savePreferences();
  }

  Future<void> _loadCAKeyFromFile() async {
    debugPrint('[IssueCertScreen] 開啟 CA 私鑰檔案');
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open CA Private Key File',
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
        setState(() => _errorMessage = 'Failed to read file as text');
        return;
      }

      if (!CertificateService.hasPrivateKeyPem(pem)) {
        setState(
            () => _errorMessage = 'No valid private key found in the file');
        return;
      }

      _loadCAKeyFromPem(pem);
    } catch (e) {
      debugPrint('[IssueCertScreen] 載入 CA 私鑰失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  void _clearCAKey() {
    debugPrint('[IssueCertScreen] 清除 CA 私鑰');
    setState(() {
      _caKeyPem = null;
      _detectedKeyType = null;
      _detectedKeySize = null;
      _detectedCurve = null;
    });
    _savePreferences();
  }

  void _useLastKey() {
    debugPrint('[IssueCertScreen] 載入剛剛建立的私鑰');
    final pem = widget.lastGeneratedKeyPem;
    if (pem != null && pem.isNotEmpty) {
      _loadCAKeyFromPem(pem);
    }
  }

  // ── CSR 解析 ──

  void _parseCSRInfo() {
    _csrSubjectCN = null;
    if (_csrPem == null) return;
    try {
      final csrData = X509Utils.csrFromPem(_csrPem!);
      final subject = csrData.certificationRequestInfo?.subject;
      if (subject != null) {
        _csrSubjectCN = subject['2.5.4.3'] ?? subject.values.firstWhere(
           (v) => v.isNotEmpty,
          orElse: () => 'Unknown',
        );
      }
    } catch (_) {
      _csrSubjectCN = 'Unknown';
    }
  }

  void _loadCSRFromPem(String pem) {
    debugPrint('[IssueCertScreen] 載入 CSR PEM: ${pem.length} 字元');
    setState(() {
      _csrPem = pem;
      _parseCSRInfo();
    });
    _savePreferences();
  }

  Future<void> _loadCSRFromFile() async {
    debugPrint('[IssueCertScreen] 開啟 CSR 檔案');
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open CSR File',
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
        setState(() => _errorMessage = 'Failed to read file as text');
        return;
      }

      if (!pem.contains('BEGIN CERTIFICATE REQUEST') &&
          !pem.contains('BEGIN NEW CERTIFICATE REQUEST')) {
        setState(() => _errorMessage = 'No valid CSR found in the file');
        return;
      }

      _loadCSRFromPem(pem);
    } catch (e) {
      debugPrint('[IssueCertScreen] 載入 CSR 失敗: $e');
      setState(() => _errorMessage = e.toString());
    }
  }

  void _clearCSR() {
    debugPrint('[IssueCertScreen] 清除 CSR');
    setState(() {
      _csrPem = null;
      _csrSubjectCN = null;
    });
    _savePreferences();
  }

  void _useLastCSR() {
    debugPrint('[IssueCertScreen] 載入剛剛建立的 CSR');
    final pem = widget.lastGeneratedCSRPem;
    if (pem != null && pem.isNotEmpty) {
      _loadCSRFromPem(pem);
    }
  }

  // ── 簽發憑證 ──

  void _issueCertificate() {
    final l10n = AppLocalizations.of(context);
    debugPrint(
      '[IssueCertScreen] 簽發憑證: days=$_validityDays, '
      'sigAlgo=$_signatureAlgorithm, isCA=$_isCA',
    );

    // UTCTime 上限檢查
    final maxDays = getMaxValidityDays();
    if (maxDays <= 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Certificate Issuance Unavailable',
              style: TextStyle(color: AppColors.textPrimary)),
          content: const Text(
            'The underlying library uses UTCTime (2-digit year) which only '
            'supports dates through 2049-12-31. Certificate generation is no '
            'longer possible after this date.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      return;
    }

    // 驗證必要輸入
    if (_caCertPem == null) {
      setState(() => _errorMessage = l10n.issueCertCACertRequired);
      return;
    }
    if (_caKeyPem == null || _detectedKeyType == null) {
      setState(() => _errorMessage = l10n.issueCertCAKeyRequired);
      return;
    }
    if (_csrPem == null) {
      setState(() => _errorMessage = l10n.issueCertCSRRequired);
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _certPem = null;
    });

    try {
      // 1. 解析 CA 私鑰
      final String keyType = _detectedKeyType!;
      final PrivateKey privateKey;

      if (keyType == 'RSA' || keyType == 'RSA_PKCS1') {
        privateKey = keyType == 'RSA_PKCS1'
            ? CryptoUtils.rsaPrivateKeyFromPemPkcs1(_caKeyPem!)
            : CryptoUtils.rsaPrivateKeyFromPem(_caKeyPem!);
      } else if (keyType == 'EC' || keyType == 'ECC') {
        privateKey = CryptoUtils.ecPrivateKeyFromPem(_caKeyPem!);
      } else {
        setState(() {
          _errorMessage = 'Unsupported key type: $keyType';
          _isGenerating = false;
        });
        return;
      }

      // 2. 從 CA 憑證提取簽發者 DN（即 CA 的 subject）
      final caCert = X509Utils.x509CertificateFromPem(_caCertPem!);
      final caSubject = caCert.tbsCertificate?.subject;
      if (caSubject == null || caSubject.isEmpty) {
        setState(() {
          _errorMessage = 'Failed to extract issuer DN from CA certificate';
          _isGenerating = false;
        });
        return;
      }
      // 轉為 Map<String, String>（過濾 null 值）
      final issuer = <String, String>{};
      for (final entry in caSubject.entries) {
        if (entry.value != null && entry.value!.isNotEmpty) {
          issuer[entry.key] = entry.value!;
        }
      }

      // 3. 取得序號或自動產生
      String serialNumber = _serialController.text.trim();
      if (serialNumber.isEmpty) {
        final rng = Random.secure();
        serialNumber =
            BigInt.from(rng.nextInt(1 << 31)).abs().toRadixString(10);
      }

      // 4. 解析路徑長度限制
      int? pathLen;
      final pathLenText = _pathLenController.text.trim();
      if (pathLenText.isNotEmpty) {
        pathLen = int.tryParse(pathLenText);
      }

      // 5. 簽發憑證
      final certPem = X509Utils.generateSelfSignedCertificate(
        privateKey,
        _csrPem!,
        _validityDays,
        issuer: issuer,
        keyUsage: _keyUsageSet.isNotEmpty ? _keyUsageSet.toList() : null,
        extKeyUsage:
            _extKeyUsageSet.isNotEmpty ? _extKeyUsageSet.toList() : null,
        cA: _isCA ? true : false,
        pathLenConstraint: _isCA ? pathLen : null,
        serialNumber: serialNumber,
        sans: _getSANList(),
      );

      setState(() {
        _certPem = certPem;
        _isGenerating = false;
      });

      debugPrint('[IssueCertScreen] 憑證簽發成功');
    } catch (e) {
      debugPrint('[IssueCertScreen] 憑證簽發失敗: $e');
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
    debugPrint('[IssueCertScreen] 已複製到剪貼簿');
  }

  Future<void> _savePem(String pem, String defaultName) async {
    debugPrint('[IssueCertScreen] 儲存檔案: $defaultName');
    try {
      final bytes = utf8.encode(pem);
      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save File',
        fileName: defaultName,
        type: FileType.any,
        bytes: bytes,
      );

      if (outputPath != null && outputPath.isNotEmpty) {
        debugPrint('[IssueCertScreen] 檔案已儲存至: $outputPath');
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
      debugPrint('[IssueCertScreen] 儲存失敗: $e');
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
    debugPrint('[IssueCertScreen] 清除結果');
    setState(() {
      _certPem = null;
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
        title: Text(l10n.menuIssueCert),
        actions: [
          if (_certPem != null)
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
                  // ── CA 憑證 ──
                  _buildSectionHeader(l10n.issueCertSectionCACert),
                  const SizedBox(height: 8),
                  _buildCACertSection(l10n),

                  // ── CA 私鑰 ──
                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.issueCertSectionCAKey),
                  const SizedBox(height: 8),
                  _buildCAKeySection(l10n),

                  // ── CSR ──
                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.issueCertSectionCSR),
                  const SizedBox(height: 8),
                  _buildCSRSection(l10n),

                  // ── 有效期與簽名 ──
                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.issueCertSectionValidity),
                  const SizedBox(height: 8),
                  _buildValiditySelector(l10n),

                  // ── 擴展 ──
                  const SizedBox(height: 16),
                  _buildSectionHeader(l10n.issueCertSectionExtensions),
                  const SizedBox(height: 8),
                  _buildKeyUsageSelector(l10n),
                  const SizedBox(height: 10),
                  _buildExtKeyUsageSelector(l10n),
                  const SizedBox(height: 10),
                  _buildBasicConstraints(l10n),
                  const SizedBox(height: 10),
                  _buildSANSection(l10n),

                  // ── 產生按鈕 ──
                  const SizedBox(height: 16),
                  _buildGenerateButton(l10n),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(l10n),
                  ],
                  if (_certPem != null) ...[
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

  // ── 通用 UI 輔助 ──

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

  /// 已載入 PEM 的狀態顯示容器（通用）
  Widget _buildLoadedPemCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onReload,
    required String reloadLabel,
    required VoidCallback onClear,
  }) {
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
          Icon(icon, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
            label: reloadLabel,
            onPressed: onReload,
          ),
          const SizedBox(width: 6),
          _IconButton(
            icon: Icons.close,
            color: AppColors.textHint,
            size: 18,
            onTap: onClear,
          ),
        ],
      ),
    );
  }

  /// 尚未載入 PEM 的文字輸入區域（通用）
  Widget _buildPemInputArea({
    required String fieldLabel,
    required String hint,
    required String? useLastLabel,
    required bool hasLast,
    required VoidCallback? onUseLast,
    required String loadFileLabel,
    required VoidCallback onLoadFile,
    required ValueChanged<String> onTextChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFieldLabel(fieldLabel, required: true),
            ),
            if (useLastLabel != null)
              hasLast
                  ? _AccentButton(
                      icon: Icons.swap_horiz_outlined,
                      label: useLastLabel,
                      onPressed: onUseLast!,
                    )
                  : Opacity(
                      opacity: 0.4,
                      child: _SmallOutlineButton(
                        icon: Icons.swap_horiz_outlined,
                        label: useLastLabel,
                        onPressed: null,
                      ),
                    ),
            const SizedBox(width: 6),
            _SmallOutlineButton(
              icon: Icons.file_open_outlined,
              label: loadFileLabel,
              onPressed: onLoadFile,
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
              hintText: hint,
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
            onChanged: onTextChanged,
          ),
        ),
      ],
    );
  }

  // ── CA 憑證區塊 ──

  Widget _buildCACertSection(AppLocalizations l10n) {
    if (_caCertPem != null && _caCertCN != null) {
      return _buildLoadedPemCard(
        icon: Icons.verified_user,
        title: l10n.issueCertCACertLoaded,
        subtitle: _caCertCN!,
        onReload: _loadCACertFromFile,
        reloadLabel: l10n.issueCertLoadCACertFile,
        onClear: _clearCACert,
      );
    }

    return _buildPemInputArea(
      fieldLabel: l10n.issueCertSectionCACert,
      hint: l10n.issueCertCACertHint,
      useLastLabel: l10n.issueCertUseLastCACert,
      hasLast: _hasLastCACert,
      onUseLast: _useLastCACert,
      loadFileLabel: l10n.issueCertLoadCACertFile,
      onLoadFile: _loadCACertFromFile,
      onTextChanged: (text) {
        if (text.contains('BEGIN CERTIFICATE')) {
          _loadCACertFromPem(text);
        }
      },
    );
  }

  // ── CA 私鑰區塊 ──

  Widget _buildCAKeySection(AppLocalizations l10n) {
    if (_caKeyPem != null && _detectedKeyType != null) {
      String desc = _detectedKeyType ?? 'Unknown';
      if (_detectedKeySize != null) desc += ' $_detectedKeySize bits';
      if (_detectedCurve != null) desc += ' ($_detectedCurve)';

      return _buildLoadedPemCard(
        icon: Icons.vpn_key,
        title: l10n.selfCAKeyLoaded,
        subtitle: desc,
        onReload: _loadCAKeyFromFile,
        reloadLabel: l10n.selfCAPrivateKeyLoad,
        onClear: _clearCAKey,
      );
    }

    return _buildPemInputArea(
      fieldLabel: l10n.selfCAPrivateKey,
      hint: l10n.selfCAPrivateKeyHint,
      useLastLabel: l10n.issueCertUseLastKey,
      hasLast: _hasLastKey,
      onUseLast: _useLastKey,
      loadFileLabel: l10n.selfCAPrivateKeyLoad,
      onLoadFile: _loadCAKeyFromFile,
      onTextChanged: (text) {
        if (CertificateService.hasPrivateKeyPem(text)) {
          _loadCAKeyFromPem(text);
        }
      },
    );
  }

  // ── CSR 區塊 ──

  Widget _buildCSRSection(AppLocalizations l10n) {
    if (_csrPem != null && _csrSubjectCN != null) {
      return _buildLoadedPemCard(
        icon: Icons.description,
        title: l10n.issueCertCSRLoaded,
        subtitle: _csrSubjectCN!,
        onReload: _loadCSRFromFile,
        reloadLabel: l10n.issueCertLoadCSRFile,
        onClear: _clearCSR,
      );
    }

    return _buildPemInputArea(
      fieldLabel: l10n.issueCertSectionCSR,
      hint: l10n.issueCertCSRHint,
      useLastLabel: l10n.issueCertUseLastCSR,
      hasLast: _hasLastCSR,
      onUseLast: _useLastCSR,
      loadFileLabel: l10n.issueCertLoadCSRFile,
      onLoadFile: _loadCSRFromFile,
      onTextChanged: (text) {
        if (text.contains('BEGIN CERTIFICATE REQUEST') ||
            text.contains('BEGIN NEW CERTIFICATE REQUEST')) {
          _loadCSRFromPem(text);
        }
      },
    );
  }

  // ── 有效期與簽名 ──

  Widget _buildValiditySelector(AppLocalizations l10n) {
    const sigAlgos = ['SHA-256', 'SHA-384', 'SHA-512'];

    return Column(
      children: [
        ValidityInput(
          initialDays: _validityDays,
          label: l10n.selfCADays,
          onChanged: (v) {
            debugPrint('[IssueCertScreen] 有效天數變更: $v');
            setState(() => _validityDays = v);
            _savePreferences();
          },
        ),
        const SizedBox(height: 8),
        _buildDropdownSelector<String>(
          label: l10n.selfCASignatureAlgorithm,
          value: _signatureAlgorithm,
          items: sigAlgos,
          itemLabel: (v) => v,
          onChanged: (v) {
            debugPrint('[IssueCertScreen] 選擇簽名演算法: $v');
            setState(() => _signatureAlgorithm = v);
            _savePreferences();
          },
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _serialController,
          label: l10n.selfCASerialNumber,
          hint: l10n.selfCASerialNumberHint,
          onChanged: (_) => _savePreferences(),
        ),
      ],
    );
  }

  // ── Key Usage ──

  Widget _buildKeyUsageSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(l10n.selfCAKeyUsage),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: KeyUsage.values.map((ku) {
            final selected = _keyUsageSet.contains(ku);
            return _buildCheckboxChip(
              label: _keyUsageLabel(ku),
              value: selected,
              onChanged: (v) {
                debugPrint(
                  '[IssueCertScreen] KeyUsage ${ku.name}: ${v ? "啟用" : "停用"}',
                );
                setState(() {
                  if (v) {
                    _keyUsageSet.add(ku);
                  } else {
                    _keyUsageSet.remove(ku);
                  }
                });
                _savePreferences();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Extended Key Usage ──

  Widget _buildExtKeyUsageSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(l10n.selfCAExtKeyUsage),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: ExtendedKeyUsage.values.map((eku) {
            final selected = _extKeyUsageSet.contains(eku);
            return _buildCheckboxChip(
              label: _extKeyUsageLabel(eku),
              value: selected,
              onChanged: (v) {
                debugPrint(
                  '[IssueCertScreen] ExtKeyUsage ${eku.name}: ${v ? "啟用" : "停用"}',
                );
                setState(() {
                  if (v) {
                    _extKeyUsageSet.add(eku);
                  } else {
                    _extKeyUsageSet.remove(eku);
                  }
                });
                _savePreferences();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Basic Constraints ──

  Widget _buildBasicConstraints(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              flex: 2,
              child: _buildTextField(
                controller: _pathLenController,
                label: l10n.selfCAPathLen,
                hint: l10n.selfCAPathLenHint,
                inputType: TextInputType.number,
                onChanged: (_) => _savePreferences(),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel(l10n.issueCertIsCA),
                  GestureDetector(
                    onTap: () {
                      debugPrint(
                          '[IssueCertScreen] 切換 isCA: ${!_isCA}');
                      setState(() => _isCA = !_isCA);
                      _savePreferences();
                    },
                    child: Container(
                      height: 44,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.primaryDark.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            _isCA
                                ? Icons.check_circle
                                : Icons.cancel_outlined,
                            color: _isCA
                                ? AppColors.success
                                : AppColors.textHint,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isCA ? 'true' : 'false',
                            style: TextStyle(
                              color: _isCA
                                  ? AppColors.textPrimary
                                  : AppColors.textHint,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
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
                _IconButton(
                  icon: Icons.remove_circle_outline,
                  color: AppColors.textHint,
                  size: 20,
                  onTap: () {
                    debugPrint('[IssueCertScreen] 刪除 SAN #$idx');
                    entry.dispose();
                    setState(() => _sanEntries.removeAt(idx));
                    _savePreferences();
                  },
                ),
              ],
            ),
          );
        }),
        _SmallOutlineButton(
          icon: Icons.add_outlined,
          label: l10n.selfCASANAdd,
          onPressed: () {
            debugPrint('[IssueCertScreen] 新增 SAN');
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
        onPressed: _isGenerating ? null : _issueCertificate,
        icon: _isGenerating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              )
            : const Icon(Icons.assignment_turned_in_outlined, size: 20),
        label: Text(
          _isGenerating ? 'Issuing...' : l10n.issueCertGenerate,
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
    final certPem = _certPem!;
    final cnPart = _csrSubjectCN ?? 'cert';
    final defaultFileName = 'issued_${cnPart}_${_detectedKeyType ?? "key"}.pem';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              l10n.issueCertResultTitle,
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
              certPem,
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
              label: l10n.issueCertCopyPem,
              onPressed: () => _copyPem(certPem),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.save_outlined,
              label: l10n.issueCertSavePem,
              onPressed: () => _savePem(certPem, defaultFileName),
            ),
            if (widget.onViewDetails != null) ...[
              const Spacer(),
              _ActionChip(
                icon: Icons.visibility_outlined,
                label: l10n.selfCAViewDetails,
                onPressed: () => widget.onViewDetails!(certPem),
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

  Widget _buildCheckboxChip({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final borderColor = value
        ? AppColors.primary
        : AppColors.primaryDark.withValues(alpha: 0.3);
    final bgColor = value
        ? AppColors.primary.withValues(alpha: 0.15)
        : AppColors.surface;
    final textColor = value ? AppColors.primary : AppColors.textHint;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: value ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 標籤輔助 ──

  String _keyUsageLabel(KeyUsage ku) {
    switch (ku) {
      case KeyUsage.DIGITAL_SIGNATURE:
        return 'Digital Signature';
      case KeyUsage.NON_REPUDIATION:
        return 'Non-Repudiation';
      case KeyUsage.KEY_ENCIPHERMENT:
        return 'Key Encipherment';
      case KeyUsage.DATA_ENCIPHERMENT:
        return 'Data Encipherment';
      case KeyUsage.KEY_AGREEMENT:
        return 'Key Agreement';
      case KeyUsage.KEY_CERT_SIGN:
        return 'Cert Sign';
      case KeyUsage.CRL_SIGN:
        return 'CRL Sign';
      case KeyUsage.ENCIPHER_ONLY:
        return 'Encipher Only';
      case KeyUsage.DECIPHER_ONLY:
        return 'Decipher Only';
    }
  }

  String _extKeyUsageLabel(ExtendedKeyUsage eku) {
    switch (eku) {
      case ExtendedKeyUsage.SERVER_AUTH:
        return 'Server Auth';
      case ExtendedKeyUsage.CLIENT_AUTH:
        return 'Client Auth';
      case ExtendedKeyUsage.CODE_SIGNING:
        return 'Code Signing';
      case ExtendedKeyUsage.EMAIL_PROTECTION:
        return 'Email';
      case ExtendedKeyUsage.TIME_STAMPING:
        return 'Time Stamping';
      case ExtendedKeyUsage.OCSP_SIGNING:
        return 'OCSP Signing';
      case ExtendedKeyUsage.BIMI:
        return 'BIMI';
    }
  }
}

// ============================================================
// 共用私有元件
// ============================================================

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
