import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/key_service.dart';
import '../theme/app_colors.dart';

/// 一鍵產生結果
class QuickGenResult {
  /// 伺服器私鑰 PEM
  final String serverKeyPem;

  /// CA 憑證 PEM
  final String caCertPem;

  /// CSR PEM
  final String csrPem;

  /// 已簽發的伺服器憑證 PEM
  final String issuedCertPem;

  /// 合併後的憑證鏈 PEM（伺服器憑證 + CA 憑證）
  final String mergedChainPem;

  const QuickGenResult({
    required this.serverKeyPem,
    required this.caCertPem,
    required this.csrPem,
    required this.issuedCertPem,
    required this.mergedChainPem,
  });
}

/// 一鍵產生畫面
///
/// 使用者只需輸入 CN（通用名稱），即可一鍵產生全套憑證檔案：
/// CA 私鑰、CA 憑證、伺服器私鑰、CSR、伺服器憑證。
class QuickGenScreen extends StatefulWidget {
  /// 產生完成後回呼，傳出全部結果
  final ValueChanged<QuickGenResult>? onGenerated;

  /// 導覽至匯出畫面的回呼
  final VoidCallback? onGoExport;

  const QuickGenScreen({super.key, this.onGenerated, this.onGoExport});

  @override
  State<QuickGenScreen> createState() => _QuickGenScreenState();
}

/// 步驟狀態
enum _StepStatus { pending, running, done, error }

/// 單一步驟
class _GenStep {
  final String label;
  _StepStatus status;
  String? errorMessage;

  _GenStep({required this.label}) : status = _StepStatus.pending;
}

class _QuickGenScreenState extends State<QuickGenScreen> {
  final TextEditingController _cnController = TextEditingController();

  /// 是否正在產生
  bool _isGenerating = false;

  /// 產生完成
  bool _isDone = false;

  /// 錯誤訊息
  String? _errorMessage;

  /// 步驟列表（動態產生以取得本地化文字）
  List<_GenStep>? _steps;

  /// 產生結果
  QuickGenResult? _result;

  @override
  void dispose() {
    _cnController.dispose();
    super.dispose();
  }

  /// 建立步驟列表
  List<_GenStep> _buildSteps(AppLocalizations l10n) {
    return [
      _GenStep(label: l10n.quickGenStepCAKey),
      _GenStep(label: l10n.quickGenStepCACert),
      _GenStep(label: l10n.quickGenStepServerKey),
      _GenStep(label: l10n.quickGenStepCSR),
      _GenStep(label: l10n.quickGenStepCert),
      _GenStep(label: l10n.quickGenStepMerge),
    ];
  }

  /// 執行一鍵產生
  Future<void> _generate() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String cn = _cnController.text.trim();

    if (cn.isEmpty) {
      setState(() => _errorMessage = l10n.errorCNRequired);
      return;
    }

    debugPrint('[QuickGenScreen] 開始一鍵產生: CN=$cn');

    final List<_GenStep> steps = _buildSteps(l10n);
    setState(() {
      _isGenerating = true;
      _isDone = false;
      _errorMessage = null;
      _result = null;
      _steps = steps;
    });

    try {
      // ── 步驟 1: 產生 CA 私鑰 ──
      _setStepRunning(0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final KeyGenerationResult caKeyResult = KeyService.generateKeyPair(
        keyType: 'rsa',
        rsaKeySize: 2048,
      );
      debugPrint('[QuickGenScreen] CA 私鑰已產生');
      _setStepDone(0);

      // ── 步驟 2: 產生自簽名 CA 憑證 ──
      _setStepRunning(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final RSAPrivateKey caPrivKey =
          caKeyResult.keyPair.privateKey as RSAPrivateKey;
      final RSAPublicKey caPubKey =
          caKeyResult.keyPair.publicKey as RSAPublicKey;

      final Map<String, String> caAttributes = {
        'CN': '$cn CA',
        'O': cn,
      };

      final String caCsrPem = X509Utils.generateRsaCsrPem(
        caAttributes,
        caPrivKey,
        caPubKey,
        signingAlgorithm: 'SHA-256',
      );

      final String serialCA = BigInt.from(Random.secure().nextInt(1 << 31))
          .abs()
          .toRadixString(10);

      final String caCertPem = X509Utils.generateSelfSignedCertificate(
        caPrivKey,
        caCsrPem,
        3650,
        keyUsage: [KeyUsage.KEY_CERT_SIGN, KeyUsage.CRL_SIGN],
        cA: true,
        serialNumber: serialCA,
      );
      debugPrint('[QuickGenScreen] CA 憑證已產生');
      _setStepDone(1);

      // ── 步驟 3: 產生伺服器私鑰 ──
      _setStepRunning(2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final KeyGenerationResult serverKeyResult = KeyService.generateKeyPair(
        keyType: 'rsa',
        rsaKeySize: 2048,
      );
      debugPrint('[QuickGenScreen] 伺服器私鑰已產生');
      _setStepDone(2);

      // ── 步驟 4: 產生 CSR ──
      _setStepRunning(3);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final RSAPrivateKey serverPrivKey =
          serverKeyResult.keyPair.privateKey as RSAPrivateKey;
      final RSAPublicKey serverPubKey =
          serverKeyResult.keyPair.publicKey as RSAPublicKey;

      final Map<String, String> serverAttributes = {'CN': cn};

      final String csrPem = X509Utils.generateRsaCsrPem(
        serverAttributes,
        serverPrivKey,
        serverPubKey,
        signingAlgorithm: 'SHA-256',
        san: [cn],
      );
      debugPrint('[QuickGenScreen] CSR 已產生');
      _setStepDone(3);

      // ── 步驟 5: 簽發伺服器憑證 ──
      _setStepRunning(4);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 從 CA 憑證取得簽發者 DN
      final X509CertificateData caCert =
          X509Utils.x509CertificateFromPem(caCertPem);
      final Map<String, String?> caSubjectRaw =
          caCert.tbsCertificate?.subject ?? {};
      final Map<String, String> issuer = {};
      for (final MapEntry<String, String?> entry in caSubjectRaw.entries) {
        if (entry.value != null && entry.value!.isNotEmpty) {
          issuer[entry.key] = entry.value!;
        }
      }

      final String serialCert = BigInt.from(Random.secure().nextInt(1 << 31))
          .abs()
          .toRadixString(10);

      final String issuedCertPem = X509Utils.generateSelfSignedCertificate(
        caPrivKey,
        csrPem,
        365,
        issuer: issuer,
        keyUsage: [KeyUsage.DIGITAL_SIGNATURE, KeyUsage.KEY_ENCIPHERMENT],
        extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
        cA: false,
        serialNumber: serialCert,
        sans: [cn],
      );
      debugPrint('[QuickGenScreen] 伺服器憑證已簽發');
      _setStepDone(4);

      // ── 步驟 6: 合併憑證鏈 ──
      _setStepRunning(5);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final StringBuffer chainBuf = StringBuffer();
      chainBuf.write(issuedCertPem.trim());
      chainBuf.write('\n');
      chainBuf.write(caCertPem.trim());
      final String mergedChainPem = chainBuf.toString();

      debugPrint('[QuickGenScreen] 憑證鏈已合併');
      _setStepDone(5);

      // ── 完成 ──
      final QuickGenResult result = QuickGenResult(
        serverKeyPem: serverKeyResult.privateKeyPem,
        caCertPem: caCertPem,
        csrPem: csrPem,
        issuedCertPem: issuedCertPem,
        mergedChainPem: mergedChainPem,
      );

      setState(() {
        _isGenerating = false;
        _isDone = true;
        _result = result;
      });

      debugPrint('[QuickGenScreen] 一鍵產生完成，共 6 個項目');
      widget.onGenerated?.call(result);
    } catch (e) {
      debugPrint('[QuickGenScreen] 一鍵產生失敗: $e');

      // 將目前正在執行的步驟標為錯誤
      if (_steps != null) {
        for (final _GenStep step in _steps!) {
          if (step.status == _StepStatus.running) {
            step.status = _StepStatus.error;
            step.errorMessage = e.toString();
          }
        }
      }

      setState(() {
        _isGenerating = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// 設定步驟為執行中
  void _setStepRunning(int index) {
    setState(() {
      _steps![index].status = _StepStatus.running;
    });
  }

  /// 設定步驟為完成
  void _setStepDone(int index) {
    setState(() {
      _steps![index].status = _StepStatus.done;
    });
  }

  /// 清除所有欄位
  void _clearAll() {
    debugPrint('[QuickGenScreen] 清除所有欄位');
    setState(() {
      _cnController.clear();
      _isGenerating = false;
      _isDone = false;
      _errorMessage = null;
      _steps = null;
      _result = null;
    });
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.quickGenTitle),
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // ── CN 輸入 ──
            _buildCNInput(l10n),
            const SizedBox(height: 16),

            // ── 產生按鈕 ──
            _buildGenerateButton(l10n),

            // ── 錯誤提示 ──
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorBanner(l10n),
            ],

            // ── 步驟進度 ──
            if (_steps != null) ...[
              const SizedBox(height: 20),
              _buildStepsSection(l10n),
            ],

            // ── 成功提示與導覽按鈕 ──
            if (_isDone && _result != null) ...[
              const SizedBox(height: 20),
              _buildSuccessSection(l10n),
            ],
          ],
        ),
      ),
    );
  }

  /// CN 輸入欄位
  Widget _buildCNInput(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                l10n.quickGenCNLabel,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
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
        ),
        SizedBox(
          height: 44,
          child: TextField(
            controller: _cnController,
            enabled: !_isGenerating,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: l10n.quickGenCNHint,
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              filled: true,
              fillColor: AppColors.surface,
              prefixIcon: const Icon(
                Icons.language_outlined,
                color: AppColors.textHint,
                size: 20,
              ),
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
            onSubmitted: (_) {
              if (!_isGenerating) _generate();
            },
          ),
        ),
      ],
    );
  }

  /// 產生按鈕
  Widget _buildGenerateButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isGenerating ? null : _generate,
        icon: _isGenerating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              )
            : const Icon(Icons.flash_on_outlined, size: 22),
        label: Text(
          _isGenerating ? l10n.quickGenGenerating : l10n.quickGenButton,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
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

  /// 錯誤提示橫幅
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

  /// 步驟進度列表
  Widget _buildStepsSection(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primaryDark.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _steps!.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _buildStepRow(_steps![i], i + 1),
          ],
        ],
      ),
    );
  }

  /// 單一步驟行
  Widget _buildStepRow(_GenStep step, int number) {
    final IconData icon;
    final Color color;
    switch (step.status) {
      case _StepStatus.pending:
        icon = Icons.radio_button_unchecked;
        color = AppColors.textHint;
      case _StepStatus.running:
        icon = Icons.hourglass_top_outlined;
        color = AppColors.primary;
      case _StepStatus.done:
        icon = Icons.check_circle_outlined;
        color = AppColors.success;
      case _StepStatus.error:
        icon = Icons.error_outline;
        color = AppColors.error;
    }

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            step.label,
            style: TextStyle(
              color: step.status == _StepStatus.pending
                  ? AppColors.textHint
                  : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: step.status == _StepStatus.running
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  /// 成功提示與導覽至匯出
  Widget _buildSuccessSection(AppLocalizations l10n) {
    final String cn = _cnController.text.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 22, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.quickGenSuccess,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.quickGenResultSummary(6, cn),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: widget.onGoExport,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(
                l10n.quickGenGoExport,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success.withValues(alpha: 0.2),
                foregroundColor: AppColors.success,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(
                    color: AppColors.success.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
