# EvernightSeal

**自簽名 SSL 憑證產生工具。**

於本地端一鍵產生自簽名 SSL / TLS 憑證與私密金鑰，適用於開發測試、內部網路或封閉環境下的 HTTPS 需求。

## 功能概要

- 產生 RSA 或 ECDSA 自簽名根憑證（Root CA）
- 產生伺服器憑證（Server Certificate）與對應私密金鑰
- 支援 SAN（Subject Alternative Name）自訂
- 匯出標準 PEM 格式檔案
- 深色新擬物化（Neumorphism）介面設計

## 編譯

### 前置需求

1. Flutter：可於 `pubspec.yaml` 中 `dependencies:flutter:` 註解處查閱最佳 Flutter 版本。
2. 執行 `flutter doctor` 指令，依提示完成各項設定。
3. `cd` 進入本專案所在資料夾。

### 除錯

1. 執行 `flutter clean` 清除快取。
2. 執行 `flutter pub get` 下載所需第三方套件。
3. 執行 `flutter gen-l10n` 產生本地化文字。
4. 執行 `flutter run` 啟動除錯。

### 建置

#### Windows

- 執行 `build.bat`。

#### macOS 或 Linux

- 執行 `./build.sh`。

## 單元測試

- 執行所有測試：`flutter test`
- 執行並顯示詳細輸出：`flutter test --reporter expanded`
- 執行測試並產生覆蓋率報告：`flutter test --coverage`

## 隱私

本程式完全開放原始碼、免費，且尊重您的隱私。

本程式僅於以下情境使用權限，您可在系統設定中停用其所有權限。

- **寫入**檔案系統：
  - 匯出產生的憑證與金鑰檔案時。
- 網路連線：
  - **本程式不會產生任何網路連線。** 為防止供應鏈攻擊或套件遭未授權修改，建議您在作業系統中完全停用本應用程式的網路存取權限。

## License

```LICENSE
Copyright (c) 2026 KagurazakaYashi(KagurazakaMiyabi)
EvernightSeal is licensed under Mulan PSL v2.
You can use this software according to the terms and conditions of the Mulan PSL v2.
You may obtain a copy of Mulan PSL v2 at:
         http://license.coscl.org.cn/MulanPSL2
THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
See the Mulan PSL v2 for more details.
```
