// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';

void main() {
  print('=== Replicating exact user flow ===\n');

  // Step 1: Generate key using KeyService-like code
  print('1. Generate RSA 2048 key pair...');
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final rsaPriv = keyPair.privateKey as RSAPrivateKey;
  final privPem = CryptoUtils.encodeRSAPrivateKeyToPem(rsaPriv);

  // Step 2: Parse back key (same as _generateCA)
  print('2. Parse back key from PEM...');
  final keyType = CryptoUtils.getPrivateKeyType(privPem);
  print('   Detected: $keyType');
  final parsedPriv = keyType == 'RSA_PKCS1'
      ? CryptoUtils.rsaPrivateKeyFromPemPkcs1(privPem)
      : CryptoUtils.rsaPrivateKeyFromPem(privPem);
  final derivedPub = RSAPublicKey(
      parsedPriv.modulus!, parsedPriv.publicExponent ?? BigInt.from(65537));

  // Step 3: Create DN attributes (exact same as user: CN=123)
  print('3. Create DN: CN=123...');
  final attributes = <String, String>{'CN': '123'};

  // Step 4: Generate CSR
  print('4. Generate CSR...');
  final csrPem = X509Utils.generateRsaCsrPem(
    attributes,
    parsedPriv,
    derivedPub,
    signingAlgorithm: 'SHA-256',
  );

  // Step 5: Generate self-signed cert (same params as user with decimal serial)
  print('5. Generate self-signed cert (CA=true, keyUsage=[CertSign,CRLSign])...');
  final serial = BigInt.from(Random.secure().nextInt(1 << 31))
      .abs()
      .toRadixString(10);
  print('   Serial: $serial');

  final certPem = X509Utils.generateSelfSignedCertificate(
    parsedPriv,
    csrPem,
    3650,
    keyUsage: [KeyUsage.KEY_CERT_SIGN, KeyUsage.CRL_SIGN],
    cA: true,
    serialNumber: serial,
  );
  print('   Cert PEM length: ${certPem.length}');
  print('   Cert PEM first line: ${certPem.split(RegExp(r'[\r\n]')).first}');

  // Step 6: Manual parsing test
  print('\n6. Manual base64 verification...');
  final begin = certPem.indexOf('-----BEGIN CERTIFICATE-----');
  final end = certPem.indexOf('-----END CERTIFICATE-----');
  final block = certPem.substring(begin, end + '-----END CERTIFICATE-----'.length);
  final normBlock = block.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normBlock.split('\n');
  final base64Text = lines.where((l) => !l.startsWith('-----') && l.isNotEmpty).join();
  try {
    final decoded = base64.decode(base64Text);
    print('   Base64 decode OK: ${decoded.length} bytes (expected ~${(certPem.length / 4 * 3).round()})');
  } catch (e) {
    print('   Base64 decode FAILED: $e');
  }

  // Step 7: x509CertificateFromPem directly
  print('\n7. Direct x509CertificateFromPem...');
  try {
    final x509 = X509Utils.x509CertificateFromPem(certPem);
    print('   SUCCESS! Subject: ${x509.tbsCertificate?.subject}');
  } catch (e) {
    print('   FAILED: $e');
  }

  // Step 8: Simulate CertificateService.parsePemText flow
  print('\n8. Simulate CertificateService flow...');
  _simulateParsePemText(certPem);

  // Step 9: Test with what the app actually does (normalized input)
  print('\n9. Simulate with normalized input (as in app)...');
  final normalized = certPem.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  _simulateParsePemText(normalized);

  print('\n=== Test Complete ===');
}

void _simulateParsePemText(String pemText) {
  // Same logic as CertificateService.parsePemText
  final text = pemText.trim();
  print('   Text length: ${text.length}, contains BEGIN: ${text.contains('-----BEGIN CERTIFICATE-----')}');

  if (text.isEmpty) {
    print('   FAILED: empty input');
    return;
  }

  // Extract PEM blocks
  final blocks = _extractPemBlocks(text);
  print('   Extracted ${blocks.length} PEM block(s)');

  if (blocks.isEmpty) {
    print('   FAILED: no PEM blocks');
    return;
  }

  // Try to parse each block
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final blockNorm = block.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    print('   Block $i: ${block.length} chars, normalized: ${blockNorm.length} chars');

    try {
      final x509 = X509Utils.x509CertificateFromPem(block);
      print('   Block $i: Parsed OK! Subject: ${x509.tbsCertificate?.subject}');
    } catch (e, st) {
      print('   Block $i: x509CertificateFromPem FAILED: $e');
      final stStr = st.toString();
      if (stStr.length > 200) {
        print('   First 200 of stack: ${stStr.substring(0, 200)}');
      } else {
        print('   Stack: $stStr');
      }

      // Try with block normalized
      try {
        final x509 = X509Utils.x509CertificateFromPem(blockNorm);
        print('   Block $i (normalized): Parsed OK!');
      } catch (e2) {
        print('   Block $i (normalized): Still FAILED: $e2');

        // Try manual base64 extraction
        try {
          final lines = blockNorm.split('\n');
          final b64 = lines.where((l) => !l.startsWith('-----') && l.isNotEmpty).join();
          print('   Manual base64: ${b64.length} chars');
          final decoded = base64.decode(b64);
          print('   Manual base64 decode OK: ${decoded.length} bytes');
        } catch (e3) {
          print('   Manual base64 decode also FAILED: $e3');
        }
      }
    }
  }
}

List<String> _extractPemBlocks(String text) {
  final blocks = <String>[];
  final beginMarkers = [
    '-----BEGIN CERTIFICATE-----',
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
