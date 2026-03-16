import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 建立私鑰畫面
class CreateKeyScreen extends StatelessWidget {
  const CreateKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('建立私鑰')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('建立私鑰 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
