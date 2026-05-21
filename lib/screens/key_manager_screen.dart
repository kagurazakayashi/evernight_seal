import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 金鑰管理畫面
class KeyManagerScreen extends StatelessWidget {
  const KeyManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuKeyManager)),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Center(
          child: Text(l10n.menuKeyManager, style: const TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
