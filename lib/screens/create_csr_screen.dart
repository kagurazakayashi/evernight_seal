import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 建立憑證請求畫面
class CreateCSRScreen extends StatelessWidget {
  const CreateCSRScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('建立憑證請求')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('建立憑證請求 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
