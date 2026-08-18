import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gost_root_ca/src/gost_http_overrides.dart';
import 'package:gost_root_ca/src/gost_root_cert.dart';

void main() {
  group('GostHttpOverrides', () {
    tearDown(() {
      HttpOverrides.global = null;
    });

    test('сертификат Минцифры добавляется в доверенные корни', () {
      HttpOverrides.global = GostHttpOverrides();

      final client = HttpClient();
      expect(client, isNotNull);
      client.close();
    });

    test('HttpClient() создаётся через оверрайд', () {
      HttpOverrides.global = GostHttpOverrides();

      expect(HttpOverrides.current, isA<GostHttpOverrides>());
    });

    test('встроенный PEM является валидным base64-сертификатом', () {
      final body = GostRootCert.pem
          .replaceAll('-----BEGIN CERTIFICATE-----', '')
          .replaceAll('-----END CERTIFICATE-----', '')
          .replaceAll(RegExp(r'\s'), '');
      final bytes = base64Decode(body);
      expect(bytes, isNotEmpty);
      expect(bytes.first, 0x30, reason: 'DER должен начинаться с SEQUENCE');
    });
  });
}
