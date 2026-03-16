import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 自簽名 CA 憑證畫面
class SelfCAScreen extends StatelessWidget {
  const SelfCAScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自簽名 CA 憑證')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: const Center(
          child: Text('自簽名 CA 憑證 - 待實作', style: TextStyle(color: AppColors.textHint)),
        ),
      ),
    );
  }
}
