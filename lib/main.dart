import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 註冊自訂授權資訊，讓授權頁面可顯示 LICENSE 與隱私權文件內容。
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('LICENSE');
    final privacy = await rootBundle.loadString('PRIVACY.md');

    yield LicenseEntryWithLineBreaks(
      ['EvernightSeal', 'License'],
      license,
    );

    yield LicenseEntryWithLineBreaks(
      ['EvernightSeal', 'Privacy'],
      privacy,
    );
  });

  runApp(const EvernightSealApp());
}

/// 長夜印信 - 自簽名 SSL 憑證產生工具
class EvernightSealApp extends StatelessWidget {
  const EvernightSealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EvernightSeal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('ja'),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        // 優先匹配語言代碼，繁體中文需特殊處理
        for (final supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode &&
              supportedLocale.scriptCode == locale?.scriptCode) {
            return supportedLocale;
          }
        }
        for (final supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode) {
            return supportedLocale;
          }
        }
        return supportedLocales.first;
      },
      home: const HomeScreen(),
    );
  }
}
