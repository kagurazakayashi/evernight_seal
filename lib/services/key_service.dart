import 'package:basic_utils/basic_utils.dart';

/// 金鑰生成結果
class KeyGenerationResult {
  /// 私鑰 PEM 字串
  final String privateKeyPem;

  /// 公開金鑰 PEM 字串
  final String publicKeyPem;

  /// 原始金鑰對
  final AsymmetricKeyPair keyPair;

  const KeyGenerationResult({
    required this.privateKeyPem,
    required this.publicKeyPem,
    required this.keyPair,
  });
}

/// 金鑰服務層 - 封裝 basic_utils 的金鑰生成功能
class KeyService {
  /// RSA 支援的金鑰長度列表
  static const List<int> rsaKeySizes = [1024, 2048, 3072, 4096, 8192];

  /// EC 支援的常用曲線列表
  static const List<String> ecCurves = [
    'prime256v1',
    'secp384r1',
    'secp521r1',
    'secp256k1',
    'secp224r1',
    'brainpoolp256r1',
    'brainpoolp384r1',
    'brainpoolp512r1',
  ];

  /// 生成 RSA 或 EC 金鑰對
  ///
  /// [keyType] 金鑰類型：'rsa' 或 'ec'
  /// [rsaKeySize] RSA 金鑰長度（位元），僅在 [keyType] 為 'rsa' 時有效
  /// [ecCurve] EC 曲線名稱，僅在 [keyType] 為 'ec' 時有效
  static KeyGenerationResult generateKeyPair({
    required String keyType,
    int rsaKeySize = 2048,
    String ecCurve = 'prime256v1',
  }) {
    if (keyType == 'rsa') {
      return _generateRsaKeyPair(rsaKeySize);
    } else {
      return _generateEcKeyPair(ecCurve);
    }
  }

  /// 生成 RSA 金鑰對
  static KeyGenerationResult _generateRsaKeyPair(int keySize) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;

    // PKCS#8 格式
    final privatePem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    final publicPem = CryptoUtils.encodeRSAPublicKeyToPem(publicKey);

    return KeyGenerationResult(
      privateKeyPem: privatePem,
      publicKeyPem: publicPem,
      keyPair: pair,
    );
  }

  /// 生成 EC 金鑰對
  static KeyGenerationResult _generateEcKeyPair(String curve) {
    final pair = CryptoUtils.generateEcKeyPair(curve: curve);
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;

    final privatePem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);
    final publicPem = CryptoUtils.encodeEcPublicKeyToPem(publicKey);

    return KeyGenerationResult(
      privateKeyPem: privatePem,
      publicKeyPem: publicPem,
      keyPair: pair,
    );
  }

  /// 取得 EC 曲線對應的位元強度
  static int? getEcCurveBitLength(String curveName) {
    const map = <String, int>{
      'prime256v1': 256,
      'secp384r1': 384,
      'secp521r1': 521,
      'secp256k1': 256,
      'secp224r1': 224,
      'secp192r1': 192,
      'secp160r1': 160,
      'secp128r1': 128,
      'secp112r1': 112,
      'brainpoolp256r1': 256,
      'brainpoolp256t1': 256,
      'brainpoolp384r1': 384,
      'brainpoolp384t1': 384,
      'brainpoolp512r1': 512,
      'brainpoolp512t1': 512,
    };
    return map[curveName];
  }
}
