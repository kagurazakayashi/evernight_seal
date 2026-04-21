import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/key_service.dart';
import '../theme/app_colors.dart';

/// 建立私鑰畫面
///
/// 提供使用者選擇加密演算法（RSA / EC）、金鑰長度或曲線，
/// 並生成對應的私鑰與公鑰 PEM 格式。
class CreateKeyScreen extends StatefulWidget {
  final ValueChanged<String>? onKeyGenerated;

  const CreateKeyScreen({super.key, this.onKeyGenerated});

  @override
  State<CreateKeyScreen> createState() => _CreateKeyScreenState();
}

class _CreateKeyScreenState extends State<CreateKeyScreen> {
  // ── 選項狀態 ──
  String _keyType = 'rsa';
  int _rsaKeySize = 2048;
  String _ecCurve = 'prime256v1';

  // ── 偏好持久化 ──
  SharedPreferences? _prefs;

  // ── 結果狀態 ──
  KeyGenerationResult? _result;
  String? _errorMessage;
  bool _isGenerating = false;

  /// 當前選中的金鑰顯示索引（0: 私鑰, 1: 公鑰）
  int _selectedKeyTab = 0;

  static const _prefKeyType = 'createKey_type';
  static const _prefRsaSize = 'createKey_rsaSize';
  static const _prefEcCurve = 'createKey_ecCurve';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    setState(() {
      _keyType = prefs.getString(_prefKeyType) ?? 'rsa';
      _rsaKeySize = prefs.getInt(_prefRsaSize) ?? 2048;
      _ecCurve = prefs.getString(_prefEcCurve) ?? 'prime256v1';
    });

    debugPrint(
      '[CreateKeyScreen] 載入偏好: type=$_keyType, '
      'rsaSize=$_rsaKeySize, ecCurve=$_ecCurve',
    );
  }

  Future<void> _savePreferences() async {
    await _prefs?.setString(_prefKeyType, _keyType);
    await _prefs?.setInt(_prefRsaSize, _rsaKeySize);
    await _prefs?.setString(_prefEcCurve, _ecCurve);
    debugPrint(
      '[CreateKeyScreen] 已儲存偏好: type=$_keyType, '
      'rsaSize=$_rsaKeySize, ecCurve=$_ecCurve',
    );
  }

  void _generateKey() {
    debugPrint(
      '[CreateKeyScreen] 生成金鑰: type=$_keyType, '
      'rsaSize=$_rsaKeySize, ecCurve=$_ecCurve',
    );

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = KeyService.generateKeyPair(
        keyType: _keyType,
        rsaKeySize: _rsaKeySize,
        ecCurve: _ecCurve,
      );

      setState(() {
        _result = result;
        _isGenerating = false;
        _selectedKeyTab = 0;
      });

      debugPrint('[CreateKeyScreen] 金鑰生成成功');
      // 通知外部有新私鑰可用
      widget.onKeyGenerated?.call(result.privateKeyPem);
    } catch (e) {
      debugPrint('[CreateKeyScreen] 金鑰生成失敗: $e');
      setState(() {
        _errorMessage = e.toString();
        _isGenerating = false;
      });
    }
  }

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
    debugPrint('[CreateKeyScreen] 已複製到剪貼簿');
  }

  Future<void> _saveKey(String pem, String defaultName) async {
    debugPrint('[CreateKeyScreen] 儲存金鑰檔案: $defaultName');

    try {
      final bytes = utf8.encode(pem);
      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save Key File',
        fileName: defaultName,
        type: FileType.any,
        bytes: bytes,
      );

      if (outputPath != null && outputPath.isNotEmpty) {
        debugPrint('[CreateKeyScreen] 金鑰已儲存至: $outputPath');

        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.createKeySave}: $outputPath'),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.surface,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CreateKeyScreen] 儲存失敗: $e');
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
    debugPrint('[CreateKeyScreen] 清除結果');
    setState(() {
      _result = null;
      _errorMessage = null;
    });
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuCreateKey),
        actions: [
          if (_result != null)
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
                  _buildAlgorithmSelector(l10n),
                  const SizedBox(height: 16),
                  _buildParameterSelector(l10n),
                  const SizedBox(height: 16),
                  _buildGenerateButton(l10n),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(l10n),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    _buildResultSection(l10n),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 演算法選擇器（RSA / EC 分段按鈕）
  Widget _buildAlgorithmSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.certViewAlgorithm,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _AlgorithmCard(
                label: 'RSA',
                icon: Icons.lock_outline,
                isSelected: _keyType == 'rsa',
                onTap: () {
                  debugPrint('[CreateKeyScreen] 選擇演算法: RSA');
                  setState(() => _keyType = 'rsa');
                  _savePreferences();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AlgorithmCard(
                label: 'EC',
                icon: Icons.show_chart_outlined,
                isSelected: _keyType == 'ec',
                onTap: () {
                  debugPrint('[CreateKeyScreen] 選擇演算法: EC');
                  setState(() => _keyType = 'ec');
                  _savePreferences();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 參數選擇器（依金鑰類型顯示金鑰長度或曲線下拉）
  Widget _buildParameterSelector(AppLocalizations l10n) {
    if (_keyType == 'rsa') {
      return _buildDropdownSelector(
        label: l10n.certViewKeySize,
        value: _rsaKeySize,
        items: KeyService.rsaKeySizes,
        itemLabel: (v) => '$v bits',
        onChanged: (v) {
          debugPrint('[CreateKeyScreen] 選擇 RSA 金鑰長度: $v bits');
          setState(() => _rsaKeySize = v);
          _savePreferences();
        },
      );
    } else {
      return _buildDropdownSelector(
        label: l10n.certViewCurve,
        value: _ecCurve,
        items: KeyService.ecCurves,
        itemLabel: (v) {
          final bits = KeyService.getEcCurveBitLength(v);
          return bits != null ? '$v ($bits bits)' : v;
        },
        onChanged: (v) {
          debugPrint('[CreateKeyScreen] 選擇 EC 曲線: $v');
          setState(() => _ecCurve = v);
          _savePreferences();
        },
      );
    }
  }

  /// 泛用下拉選擇器
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
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
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
                fontSize: 14,
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
                      fontSize: 14,
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

  /// 生成按鈕
  Widget _buildGenerateButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _isGenerating ? null : _generateKey,
        icon: _isGenerating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              )
            : const Icon(Icons.vpn_key_outlined, size: 20),
        label: Text(
          _isGenerating ? 'Generating...' : l10n.createKeyGenerate,
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

  /// 結果區塊
  Widget _buildResultSection(AppLocalizations l10n) {
    final result = _result!;
    final privatePem = result.privateKeyPem;
    final publicPem = result.publicKeyPem;

    final currentPem = _selectedKeyTab == 0 ? privatePem : publicPem;
    final defaultFileName = _selectedKeyTab == 0
        ? 'private_key_$_keyType.pem'
        : 'public_key_$_keyType.pem';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 分頁標題列 ──
        Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              _selectedKeyTab == 0
                  ? l10n.certViewPrivateKey
                  : l10n.createKeyPublicKey,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            // 私鑰/公鑰分頁切換
            _buildKeyTabToggle(l10n),
          ],
        ),
        const SizedBox(height: 10),

        // ── PEM 文字區塊 ──
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
              currentPem,
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

        // ── 操作按鈕列 ──
        Row(
          children: [
            _ActionChip(
              icon: Icons.copy_outlined,
              label: l10n.certViewCopyPem,
              onPressed: () => _copyPem(currentPem),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.save_outlined,
              label: l10n.createKeySave,
              onPressed: () => _saveKey(currentPem, defaultFileName),
            ),
          ],
        ),
      ],
    );
  }

  /// 私鑰 / 公鑰分頁切換
  Widget _buildKeyTabToggle(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.primaryDark.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _KeyTab(
            label: l10n.certViewPrivateKey,
            isSelected: _selectedKeyTab == 0,
            onTap: () {
              debugPrint('[CreateKeyScreen] 切換至私鑰分頁');
              setState(() => _selectedKeyTab = 0);
            },
          ),
          _KeyTab(
            label: l10n.createKeyPublicKey,
            isSelected: _selectedKeyTab == 1,
            onTap: () {
              debugPrint('[CreateKeyScreen] 切換至公鑰分頁');
              setState(() => _selectedKeyTab = 1);
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 演算法選擇卡片
// ============================================================

class _AlgorithmCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AlgorithmCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? AppColors.primary : AppColors.primaryDark.withValues(alpha: 0.3);
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

// ============================================================
// 金鑰分頁切換按鈕
// ============================================================

class _KeyTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _KeyTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryDark.withValues(alpha: 0.4) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textHint,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
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
