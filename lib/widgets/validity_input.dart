import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// UTCTime 只支援 1950–2049 年。
/// 計算從現在起到 2049-12-31 的剩餘天數作為最大有效期。
int getMaxValidityDays() {
  final now = DateTime.now().toUtc();
  final limit = DateTime.utc(2049, 12, 31, 23, 59, 59);
  final remaining = limit.difference(now).inDays;
  return remaining > 0 ? remaining : 0;
}

/// 時間單位列舉
enum ValidityUnit {
  days(1),
  months(30),
  years(365);

  final int daysPerUnit;
  const ValidityUnit(this.daysPerUnit);

  /// 依總天數算出在此單位下的顯示值
  int displayValue(int totalDays) => totalDays ~/ daysPerUnit;

  /// 將顯示值轉為總天數
  int toTotalDays(int displayValue) => displayValue * daysPerUnit;
}

/// 有效期輸入元件（可複用）
///
/// 提供數值輸入框 + 時間單位下拉，切換單位時自動換算。
/// [onChanged] 回傳總天數。
class ValidityInput extends StatefulWidget {
  /// 初始總天數
  final int initialDays;

  /// 每當總天數變更時回呼
  final ValueChanged<int>? onChanged;

  /// 欄位標籤文字
  final String? label;

  const ValidityInput({
    super.key,
    required this.initialDays,
    this.onChanged,
    this.label,
  });

  @override
  State<ValidityInput> createState() => _ValidityInputState();
}

class _ValidityInputState extends State<ValidityInput> {
  late int _totalDays;
  late ValidityUnit _unit;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _totalDays = widget.initialDays.clamp(1, getMaxValidityDays());
    // 自動選擇最合理的初始單位
    _unit = _bestUnit(_totalDays);
    _controller = TextEditingController(
      text: _unit.displayValue(_totalDays).toString(),
    );
    // 若初始值被截斷，通知上層
    if (_totalDays != widget.initialDays) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged?.call(_totalDays);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 依總天數自動選擇最合適的顯示單位
  ValidityUnit _bestUnit(int totalDays) {
    if (totalDays >= 365 && totalDays % 365 == 0) return ValidityUnit.years;
    if (totalDays >= 30 && totalDays % 30 == 0) return ValidityUnit.months;
    return ValidityUnit.days;
  }

  void _onTextChanged(String text) {
    final v = int.tryParse(text);
    if (v != null && v > 0) {
      var total = _unit.toTotalDays(v);
      final maxDays = getMaxValidityDays();
      if (total > maxDays) {
        total = maxDays;
        // 修正輸入框顯示為上限值
        final cappedDisplay = _unit.displayValue(total).toString();
        if (_controller.text != cappedDisplay) {
          _controller.text = cappedDisplay;
          // 移動游標到末尾
          _controller.selection = TextSelection.collapsed(
            offset: cappedDisplay.length,
          );
        }
      }
      _totalDays = total;
      widget.onChanged?.call(_totalDays);
    }
  }

  void _onUnitChanged(ValidityUnit newUnit) {
    if (newUnit == _unit) return;
    final oldDisplay = _unit.displayValue(_totalDays);
    final newDisplay = newUnit.displayValue(_totalDays);

    debugPrint(
      '[ValidityInput] 單位切換: $_unit → $newUnit'
      ' (總天數=$_totalDays, 顯示 $oldDisplay → $newDisplay)',
    );

    setState(() {
      _unit = newUnit;
      _controller.text = newDisplay.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            // 數值輸入框
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
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
                  onChanged: _onTextChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 單位下拉
            Expanded(
              flex: 1,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.primaryDark.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ValidityUnit>(
                    value: _unit,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                    items: ValidityUnit.values.map((u) {
                      return DropdownMenuItem(
                        value: u,
                        child: Text(
                          _unitLabel(u),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) _onUnitChanged(v);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 單位顯示文字
  String _unitLabel(ValidityUnit unit) {
    // 這裡無法直接使用 AppLocalizations（依賴 context），改用簡短英文
    switch (unit) {
      case ValidityUnit.days:
        return 'Days';
      case ValidityUnit.months:
        return 'Months';
      case ValidityUnit.years:
        return 'Years';
    }
  }
}
