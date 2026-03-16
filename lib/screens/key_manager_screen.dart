import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 金鑰管理畫面
class KeyManagerScreen extends StatelessWidget {
  const KeyManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('金鑰管理')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('金鑰管理 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
