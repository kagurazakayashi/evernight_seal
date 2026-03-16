import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 查看憑證資訊畫面
class CertViewScreen extends StatelessWidget {
  const CertViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('查看憑證')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('查看憑證資訊 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
