import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 使用 CA 簽發憑證畫面
class IssueCertScreen extends StatelessWidget {
  const IssueCertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('簽發憑證')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('使用 CA 簽發憑證 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
