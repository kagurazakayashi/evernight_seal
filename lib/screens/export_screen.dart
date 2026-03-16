import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 匯出憑證與私鑰畫面
class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('匯出')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('匯出 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
