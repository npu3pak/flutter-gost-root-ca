import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gost_root_ca/gost_root_ca.dart';

/// Корень Минцифры хранится в трёх файлах (Dart, Swift, Android res/raw).
/// Тест гарантирует, что при ротации обновили все три.
void main() {
  final pemBlock = RegExp(
    r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
    dotAll: true,
  );

  String extract(String source) {
    final match = pemBlock.firstMatch(source);
    expect(match, isNotNull, reason: 'PEM-блок не найден');
    return match!.group(0)!.trim();
  }

  test('GostBuiltinRootCert.swift содержит тот же PEM, что GostRootCert.pem', () {
    final swift = File('ios/Classes/GostBuiltinRootCert.swift').readAsStringSync();
    expect(extract(swift), extract(GostRootCert.pem));
  });

  test('Android res/raw содержит тот же PEM, что GostRootCert.pem', () {
    final android = File(
      '../gost_root_ca_android/android/src/main/res/raw/gost_russian_trusted_root_ca.pem',
    ).readAsStringSync();
    expect(extract(android), extract(GostRootCert.pem));
  });
}
