import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

/// 憑證解析結果
class CertParseResult {
  /// 解析出的憑證列表
  final List<X509CertificateData> certificates;

  /// 來源類型：pem / pkcs7 / pfx / der
  final String sourceType;

  /// 錯誤訊息（若解析失敗）
  final String? errorMessage;

  /// 是否包含私鑰（僅 PFX 可能有）
  final bool hasPrivateKey;

  const CertParseResult({
    required this.certificates,
    required this.sourceType,
    this.errorMessage,
    this.hasPrivateKey = false,
  });

  bool get isSuccess => errorMessage == null && certificates.isNotEmpty;
}

/// 私鑰資訊
class PrivateKeyInfo {
  /// 金鑰演算法：RSA / ECC
  final String algorithm;

  /// 金鑰大小（位元）
  final int? keySize;

  /// 曲線名稱（僅 ECC）
  final String? curveName;

  /// 模數（僅 RSA，十六進位字串）
  final String? modulusHex;

  /// 公開指數（僅 RSA）
  final int? publicExponent;

  /// SHA-256 指紋
  final String? sha256Thumbprint;

  /// 私鑰 PEM 原文
  final String? pemText;

  /// 是否已加密
  final bool isEncrypted;

  const PrivateKeyInfo({
    required this.algorithm,
    this.keySize,
    this.curveName,
    this.modulusHex,
    this.publicExponent,
    this.sha256Thumbprint,
    this.pemText,
    this.isEncrypted = false,
  });
}

/// 金鑰配對比對狀態
enum KeyMatchStatus { matched, mismatched, error }

/// 金鑰配對比對結果
class KeyPairMatchResult {
  /// 比對狀態
  final KeyMatchStatus status;

  /// 描述訊息（錯誤或不匹配原因）
  final String? message;

  /// 憑證公鑰演算法
  final String? certAlgorithm;

  /// 私鑰演算法
  final String? keyAlgorithm;

  /// 憑證公鑰長度
  final int? certKeySize;

  /// 私鑰長度
  final int? keyKeySize;

  const KeyPairMatchResult({
    required this.status,
    this.message,
    this.certAlgorithm,
    this.keyAlgorithm,
    this.certKeySize,
    this.keyKeySize,
  });
}

/// 憑證服務層 - 封裝 basic_utils 的憑證解析功能
class CertificateService {
  /// 從 PEM 文字解析憑證（支援單一憑證、多個 PEM 區塊、PKCS#7）
  static CertParseResult parsePemText(String pemText) {
    if (pemText.trim().isEmpty) {
      return const CertParseResult(
        certificates: [],
        sourceType: 'pem',
        errorMessage: 'No certificate data provided',
      );
    }

    // 檢查是否為 PKCS#7
    if (pemText.contains(X509Utils.BEGIN_PKCS7)) {
      return _parsePkcs7(pemText);
    }

    return _parseSingleOrMultiplePem(pemText);
  }

  /// 從二進位資料解析 PFX/P12 憑證
  static CertParseResult parsePfxBytes(
    Uint8List pfxData, {
    String? password,
  }) {
    try {
      final pemList = Pkcs12Utils.parsePkcs12(pfxData, password: password);
      final certs = <X509CertificateData>[];
      bool hasKey = false;

      for (final pem in pemList) {
        if (pem.contains('PRIVATE KEY') ||
            pem.contains('RSA PRIVATE KEY') ||
            pem.contains('EC PRIVATE KEY')) {
          hasKey = true;
          continue;
        }
        if (pem.contains('BEGIN CERTIFICATE') ||
            pem.contains('BEGIN X509')) {
          try {
            certs.add(X509Utils.x509CertificateFromPem(pem));
          } catch (_) {
            // 略過無法解析的區塊
          }
        }
      }

      if (certs.isEmpty) {
        return CertParseResult(
          certificates: [],
          sourceType: 'pfx',
          errorMessage: 'No valid certificates found in PFX file',
          hasPrivateKey: hasKey,
        );
      }

      return CertParseResult(
        certificates: certs,
        sourceType: 'pfx',
        hasPrivateKey: hasKey,
      );
    } catch (e) {
      return CertParseResult(
        certificates: [],
        sourceType: 'pfx',
        errorMessage: 'Failed to parse PFX/P12 file: ${e.toString()}',
      );
    }
  }

  /// 從 DER 二進位資料解析憑證
  static CertParseResult parseDerBytes(Uint8List derData) {
    try {
      // 將 DER 位元組包裝為 PEM 格式後解析
      final pem = '-----BEGIN CERTIFICATE-----\n'
          '${base64.encode(derData)}\n'
          '-----END CERTIFICATE-----';
      final cert = X509Utils.x509CertificateFromPem(pem);
      return CertParseResult(certificates: [cert], sourceType: 'der');
    } catch (e) {
      return CertParseResult(
        certificates: [],
        sourceType: 'der',
        errorMessage: 'Failed to parse DER certificate: ${e.toString()}',
      );
    }
  }

  /// 以啟發式方法自動判斷並解析任意憑證資料
  /// 支援 PEM 文字、DER 二進位、PFX/P12 二進位
  static CertParseResult autoParse(
    Uint8List data, {
    String? password,
  }) {
    // 嘗試作為 UTF-8 文字解析
    try {
      final text = utf8.decode(data);
      // 檢查是否包含 PEM 標頭
      if (text.contains('-----BEGIN')) {
        return parsePemText(text);
      }
      // 檢查是否為純 base64（嘗試包裝為 PEM 後解析）
      final trimmed = text.replaceAll(RegExp(r'\s'), '');
      if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(trimmed) &&
          trimmed.length > 100) {
        try {
          final derBytes = base64.decode(trimmed);
          final result = parseDerBytes(derBytes);
          if (result.isSuccess) return result;
        } catch (_) {}
        // 嘗試包裝為 PEM
        try {
          final wrapped = '-----BEGIN CERTIFICATE-----\n'
              '${_chunk(trimmed, 64)}\n'
              '-----END CERTIFICATE-----';
          final result = parsePemText(wrapped);
          if (result.isSuccess) return result;
        } catch (_) {}
      }
    } catch (_) {
      // 不是有效的 UTF-8，判斷為二進位格式
    }

    // 檢查是否為 PFX 格式（PFX 也以 0x30 開頭，但結構不同）
    if (data.length > 4 && data[0] == 0x30) {
      // 先嘗試 DER
      final derResult = parseDerBytes(data);
      if (derResult.isSuccess) return derResult;

      // 再嘗試 PFX
      final pfxResult = parsePfxBytes(data, password: password);
      if (pfxResult.isSuccess) return pfxResult;
      if (pfxResult.errorMessage != null) return pfxResult;
    }

    return const CertParseResult(
      certificates: [],
      sourceType: 'unknown',
      errorMessage: 'Unrecognized certificate format',
    );
  }

  /// OID 到短名稱的反向對照表（基於 X509Utils.DN）
  static final Map<String, String> _oidToShortName = _buildOidMap();

  /// for OID-to-name resolution
  static Map<String, String> _buildOidMap() {
    final m = <String, String>{};
    final dn = X509Utils.DN;
    // 先以短名稱為主鍵建立對照（cn、o、ou 等優先於長名稱）
    for (final entry in dn.entries) {
      final name = entry.key;
      final oid = entry.value;
      if (!name.contains(RegExp(r'[A-Z]')) && name.length <= 2) {
        m[oid] = name.toUpperCase();
      }
    }
    // 補上長名稱
    for (final entry in dn.entries) {
      final name = entry.key;
      final oid = entry.value;
      if (!m.containsKey(oid)) {
        m[oid] = name;
      }
    }
    return m;
  }

  /// 將 OID 轉換為短名稱（如 '2.5.4.3' → 'CN'）
  static String oidToName(String oid) {
    return _oidToShortName[oid] ?? oid;
  }

  /// 常見 CN OID 列表
  static const _cnOids = ['2.5.4.3'];

  /// 將 Distinguished Name Map 轉為可讀字串
  static String dnToString(Map<String, String?>? dn) {
    if (dn == null || dn.isEmpty) return '';

    // 常見 OID 的顯示順序（按 OID）
    const orderOids = [
      '2.5.4.3',  // CN
      '2.5.4.11', // OU
      '2.5.4.10', // O
      '2.5.4.7',  // L
      '2.5.4.8',  // ST
      '2.5.4.6',  // C
    ];

    final parts = <String>[];
    for (final oid in orderOids) {
      final value = dn[oid];
      if (value != null && value.isNotEmpty) {
        final name = oidToName(oid);
        parts.add('$name=$value');
      }
    }
    // 加入不在預設順序中的鍵
    for (final entry in dn.entries) {
      if (!orderOids.contains(entry.key) &&
          entry.value != null &&
          entry.value!.isNotEmpty) {
        final name = oidToName(entry.key);
        parts.add('$name=${entry.value}');
      }
    }
    return parts.join(', ');
  }

  /// 取得憑證主體 CN
  static String getSubjectCN(X509CertificateData cert) {
    final subject = cert.tbsCertificate?.subject;
    if (subject == null || subject.isEmpty) return 'Unknown';
    for (final oid in _cnOids) {
      final v = subject[oid];
      if (v != null && v.isNotEmpty) return v;
    }
    // 若無 CN，回傳第一個值
    return subject.values.firstWhere(
      (v) => v != null && v.isNotEmpty,
      orElse: () => 'Unknown',
    )!;
  }

  /// 取得憑證簽發者 CN
  static String getIssuerCN(X509CertificateData cert) {
    final issuer = cert.tbsCertificate?.issuer;
    if (issuer == null || issuer.isEmpty) return 'Unknown';
    for (final oid in _cnOids) {
      final v = issuer[oid];
      if (v != null && v.isNotEmpty) return v;
    }
    return issuer.values.firstWhere(
      (v) => v != null && v.isNotEmpty,
      orElse: () => 'Unknown',
    )!;
  }

  /// 檢查憑證是否為自簽名（主體等於簽發者）
  static bool isSelfSigned(X509CertificateData cert) {
    final subject = cert.tbsCertificate?.subject;
    final issuer = cert.tbsCertificate?.issuer;
    if (subject == null || issuer == null) return false;
    if (subject.length != issuer.length) return false;
    for (final key in subject.keys) {
      if (subject[key] != issuer[key]) return false;
    }
    return true;
  }

  /// 將 KeyUsage 轉為可讀字串
  static String keyUsageToString(KeyUsage usage) {
    switch (usage) {
      case KeyUsage.DIGITAL_SIGNATURE:
        return 'Digital Signature';
      case KeyUsage.NON_REPUDIATION:
        return 'Non-Repudiation';
      case KeyUsage.KEY_ENCIPHERMENT:
        return 'Key Encipherment';
      case KeyUsage.DATA_ENCIPHERMENT:
        return 'Data Encipherment';
      case KeyUsage.KEY_AGREEMENT:
        return 'Key Agreement';
      case KeyUsage.KEY_CERT_SIGN:
        return 'Certificate Sign';
      case KeyUsage.CRL_SIGN:
        return 'CRL Sign';
      case KeyUsage.ENCIPHER_ONLY:
        return 'Encipher Only';
      case KeyUsage.DECIPHER_ONLY:
        return 'Decipher Only';
    }
  }

  /// 將 ExtendedKeyUsage 轉為可讀字串
  static String extKeyUsageToString(ExtendedKeyUsage usage) {
    switch (usage) {
      case ExtendedKeyUsage.SERVER_AUTH:
        return 'TLS Web Server Authentication';
      case ExtendedKeyUsage.CLIENT_AUTH:
        return 'TLS Web Client Authentication';
      case ExtendedKeyUsage.CODE_SIGNING:
        return 'Code Signing';
      case ExtendedKeyUsage.EMAIL_PROTECTION:
        return 'Email Protection';
      case ExtendedKeyUsage.TIME_STAMPING:
        return 'Time Stamping';
      case ExtendedKeyUsage.OCSP_SIGNING:
        return 'OCSP Signing';
      case ExtendedKeyUsage.BIMI:
        return 'BIMI';
    }
  }

  // ---- 私有輔助方法 ----

  static CertParseResult _parsePkcs7(String pemText) {
    try {
      final pkcs7Data = X509Utils.pkcs7fromPem(pemText);
      final certs = pkcs7Data.certificates ?? [];
      if (certs.isEmpty) {
        return const CertParseResult(
          certificates: [],
          sourceType: 'pkcs7',
          errorMessage: 'No certificates found in PKCS#7 data',
        );
      }
      return CertParseResult(certificates: certs, sourceType: 'pkcs7');
    } catch (e) {
      return CertParseResult(
        certificates: [],
        sourceType: 'pkcs7',
        errorMessage: 'Failed to parse PKCS#7: ${e.toString()}',
      );
    }
  }

  static CertParseResult _parseSingleOrMultiplePem(String pemText) {
    final blocks = _extractPemBlocks(pemText);
    if (blocks.isEmpty) {
      // 嘗試將純 base64 內容包裝為 PEM 後解析
      final trimmed = pemText.replaceAll(RegExp(r'\s'), '');
      if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(trimmed) &&
          trimmed.length > 100) {
        try {
          final wrapped = '-----BEGIN CERTIFICATE-----\n'
              '${_chunk(trimmed, 64)}\n'
              '-----END CERTIFICATE-----';
          final cert = X509Utils.x509CertificateFromPem(wrapped);
          return CertParseResult(certificates: [cert], sourceType: 'pem');
        } catch (_) {}
      }
      return const CertParseResult(
        certificates: [],
        sourceType: 'pem',
        errorMessage: 'No valid PEM certificate found in the input text',
      );
    }

    final certs = <X509CertificateData>[];
    for (final pem in blocks) {
      try {
        certs.add(X509Utils.x509CertificateFromPem(pem));
      } catch (_) {
        // 略過無效區塊
      }
    }

    if (certs.isEmpty) {
      return const CertParseResult(
        certificates: [],
        sourceType: 'pem',
        errorMessage: 'Failed to parse any certificates from the input',
      );
    }

    return CertParseResult(certificates: certs, sourceType: 'pem');
  }

  /// 從文字中提取所有 PEM 憑證區塊
  static List<String> _extractPemBlocks(String text) {
    final blocks = <String>[];
    final beginMarkers = [
      X509Utils.BEGIN_CERT,
      '-----BEGIN TRUSTED CERTIFICATE-----',
      '-----BEGIN X509 CERTIFICATE-----',
    ];

    for (final begin in beginMarkers) {
      final end = begin.replaceAll('BEGIN', 'END');
      int start = 0;
      while (true) {
        final beginIdx = text.indexOf(begin, start);
        if (beginIdx == -1) break;
        final endIdx = text.indexOf(end, beginIdx);
        if (endIdx == -1) break;
        blocks.add(text.substring(beginIdx, endIdx + end.length));
        start = endIdx + end.length;
      }
    }

    return blocks;
  }

  /// 將字串按固定長度分段
  static String _chunk(String s, int size) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i += size) {
      if (i > 0) buf.write('\n');
      buf.write(s.substring(i, i + size > s.length ? s.length : i + size));
    }
    return buf.toString();
  }

  // ---- 私鑰解析 ----

  /// 私鑰 PEM 標頭
  static const _privateKeyHeaders = [
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN RSA PRIVATE KEY-----',
    '-----BEGIN EC PRIVATE KEY-----',
    '-----BEGIN ENCRYPTED PRIVATE KEY-----',
  ];

  /// 檢查 PEM 文字是否包含私鑰
  static bool hasPrivateKeyPem(String pemText) {
    return _privateKeyHeaders.any((h) => pemText.contains(h));
  }

  /// 檢查 PEM 私鑰是否已加密
  static bool isPrivateKeyEncrypted(String pemText) {
    return pemText.contains('ENCRYPTED') ||
           pemText.contains('ENCRYPTED PRIVATE KEY');
  }

  /// 從 PEM 文字中提取私鑰區塊
  static List<String> extractPrivateKeyBlocks(String pemText) {
    final blocks = <String>[];
    for (final begin in _privateKeyHeaders) {
      final end = begin.replaceAll('BEGIN', 'END');
      int start = 0;
      while (true) {
        final beginIdx = pemText.indexOf(begin, start);
        if (beginIdx == -1) break;
        final endIdx = pemText.indexOf(end, beginIdx);
        if (endIdx == -1) break;
        blocks.add(pemText.substring(beginIdx, endIdx + end.length));
        start = endIdx + end.length;
      }
    }
    return blocks;
  }

  /// 根據橢圓曲線名稱推估金鑰大小
  static int? _ecCurveBitLength(String? curveName) {
    if (curveName == null) return null;
    final m = {
      'secp256r1': 256, 'prime256v1': 256,
      'secp384r1': 384,
      'secp521r1': 521,
      'secp256k1': 256,
      'secp224r1': 224, 'secp224k1': 224,
      'secp192r1': 192, 'secp192k1': 192,
      'secp160r1': 160, 'secp160k1': 160,
      'secp128r1': 128,
      'secp112r1': 112,
      'brainpoolp256r1': 256, 'brainpoolp256t1': 256,
      'brainpoolp384r1': 384, 'brainpoolp384t1': 384,
      'brainpoolp512r1': 512, 'brainpoolp512t1': 512,
    };
    return m[curveName];
  }

  // ---- 金鑰配對比對 ----

  /// 將十六進位字串轉換為位元組陣列（等效 basic_utils 內部的 _stringAsBytes）
  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// 比對憑證與私鑰是否為配對的金鑰對
  ///
  /// 支援 RSA 與 EC 演算法。透過比對憑證公鑰與私鑰推導出的公鑰來判斷是否匹配。
  static KeyPairMatchResult matchKeyPair({
    required X509CertificateData cert,
    required String privateKeyPem,
  }) {
    try {
      final spki = cert.tbsCertificate?.subjectPublicKeyInfo;
      if (spki == null) {
        return const KeyPairMatchResult(
          status: KeyMatchStatus.error,
          message: 'Certificate has no public key info',
        );
      }

      final certAlgo = spki.algorithmReadableName ?? spki.algorithm ?? '';
      final certKeySize = spki.length;

      // 判斷私鑰類型
      if (isPrivateKeyEncrypted(privateKeyPem)) {
        return const KeyPairMatchResult(
          status: KeyMatchStatus.error,
          message: 'Private key is encrypted; cannot verify match',
        );
      }

      final keyType = CryptoUtils.getPrivateKeyType(privateKeyPem);

      // 演算法類型不匹配的快速判斷
      final certIsRsa = certAlgo.toUpperCase().contains('RSA');
      final certIsEc = certAlgo.toUpperCase().contains('EC') ||
          certAlgo.toUpperCase().contains('ECDSA');
      final keyIsRsa = keyType == 'RSA' || keyType == 'RSA_PKCS1';
      final keyIsEc = keyType == 'ECC';

      if ((certIsRsa && !keyIsRsa) || (certIsEc && !keyIsEc)) {
        return KeyPairMatchResult(
          status: KeyMatchStatus.mismatched,
          message: 'Algorithm mismatch: cert=$certAlgo, key=$keyType',
          certAlgorithm: certAlgo,
          keyAlgorithm: keyType,
          certKeySize: certKeySize,
        );
      }

      if (keyIsRsa) {
        return _matchRsa(cert, privateKeyPem, keyType, certAlgo, certKeySize);
      } else if (keyIsEc) {
        return _matchEc(cert, privateKeyPem, certAlgo, certKeySize);
      }

      return KeyPairMatchResult(
        status: KeyMatchStatus.error,
        message: 'Unsupported key type: $keyType',
        certAlgorithm: certAlgo,
        keyAlgorithm: keyType,
      );
    } catch (e) {
      return KeyPairMatchResult(
        status: KeyMatchStatus.error,
        message: e.toString(),
      );
    }
  }

  /// RSA 金鑰配對比對：比較模數 (modulus)
  static KeyPairMatchResult _matchRsa(
    X509CertificateData cert,
    String privateKeyPem,
    String keyType,
    String certAlgo,
    int? certKeySize,
  ) {
    final rsaPriv = keyType == 'RSA_PKCS1'
        ? CryptoUtils.rsaPrivateKeyFromPemPkcs1(privateKeyPem)
        : CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
    final privModulus = rsaPriv.n;
    final privKeySize = privModulus?.bitLength;

    // 從憑證的 SubjectPublicKeyInfo 提取 RSA 公鑰
    final spki = cert.tbsCertificate!.subjectPublicKeyInfo;
    final pubKeyHex = spki.bytes;
    if (pubKeyHex == null || pubKeyHex.isEmpty) {
      return KeyPairMatchResult(
        status: KeyMatchStatus.error,
        message: 'Certificate public key bytes not available',
        certAlgorithm: certAlgo,
        keyAlgorithm: 'RSA',
        certKeySize: certKeySize,
        keyKeySize: privKeySize,
      );
    }

    final pubKeyBytes = _hexToBytes(pubKeyHex);
    final rsaPub = CryptoUtils.rsaPublicKeyFromDERBytes(pubKeyBytes);

    final matched = rsaPub.modulus == privModulus;
    return KeyPairMatchResult(
      status: matched ? KeyMatchStatus.matched : KeyMatchStatus.mismatched,
      message: matched ? null : 'RSA modulus does not match',
      certAlgorithm: certAlgo,
      keyAlgorithm: 'RSA',
      certKeySize: certKeySize ?? rsaPub.modulus?.bitLength,
      keyKeySize: privKeySize,
    );
  }

  /// EC 金鑰配對比對：比較公鑰點 Q
  static KeyPairMatchResult _matchEc(
    X509CertificateData cert,
    String privateKeyPem,
    String certAlgo,
    int? certKeySize,
  ) {
    final ecPriv = CryptoUtils.ecPrivateKeyFromPem(privateKeyPem);
    final privCurve = ecPriv.parameters?.domainName;
    final privKeySize = _ecCurveBitLength(privCurve);

    // 從私鑰推導公鑰點 Q = d * G
    final derivedQ = ecPriv.parameters!.G * ecPriv.d;

    // 從憑證的 SubjectPublicKeyInfo 提取 EC 公鑰
    final spki = cert.tbsCertificate!.subjectPublicKeyInfo;
    final pubKeyHex = spki.bytes;
    if (pubKeyHex == null || pubKeyHex.isEmpty) {
      return KeyPairMatchResult(
        status: KeyMatchStatus.error,
        message: 'Certificate public key bytes not available',
        certAlgorithm: certAlgo,
        keyAlgorithm: 'EC',
        certKeySize: certKeySize,
        keyKeySize: privKeySize,
      );
    }

    final pubKeyBytes = _hexToBytes(pubKeyHex);
    final ecPub = CryptoUtils.ecPublicKeyFromDerBytes(pubKeyBytes);

    // 比較公鑰點座標
    final matched = derivedQ?.x == ecPub.Q?.x && derivedQ?.y == ecPub.Q?.y;
    return KeyPairMatchResult(
      status: matched ? KeyMatchStatus.matched : KeyMatchStatus.mismatched,
      message: matched ? null : 'EC public key point does not match',
      certAlgorithm: certAlgo,
      keyAlgorithm: 'EC ($privCurve)',
      certKeySize: certKeySize,
      keyKeySize: privKeySize,
    );
  }

  /// 解析未加密的私鑰 PEM
  static PrivateKeyInfo? parsePrivateKeyPem(String pem) {
    if (isPrivateKeyEncrypted(pem)) {
      return PrivateKeyInfo(
        algorithm: 'Unknown',
        isEncrypted: true,
        pemText: pem,
      );
    }

    try {
      final keyType = CryptoUtils.getPrivateKeyType(pem);

      if (keyType == 'RSA' || keyType == 'RSA_PKCS1') {
        final rsaKey = keyType == 'RSA_PKCS1'
            ? CryptoUtils.rsaPrivateKeyFromPemPkcs1(pem)
            : CryptoUtils.rsaPrivateKeyFromPem(pem);
        final keySize = rsaKey.n?.bitLength;

        return PrivateKeyInfo(
          algorithm: 'RSA',
          keySize: keySize,
          modulusHex: rsaKey.n?.toRadixString(16).toUpperCase(),
          publicExponent: 65537,
          pemText: pem,
        );
      } else if (keyType == 'ECC') {
        final ecKey = CryptoUtils.ecPrivateKeyFromPem(pem);
        return PrivateKeyInfo(
          algorithm: 'EC',
          keySize: _ecCurveBitLength(ecKey.parameters?.domainName),
          curveName: ecKey.parameters?.domainName,
          pemText: pem,
        );
      }
    } catch (e) {
      return PrivateKeyInfo(
        algorithm: 'Unknown',
        pemText: pem,
        isEncrypted: isPrivateKeyEncrypted(pem),
      );
    }
    return null;
  }
}
