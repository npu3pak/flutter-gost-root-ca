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

    test('HttpClient() создаётся через оверрайд', () {
      HttpOverrides.global = GostHttpOverrides();

      expect(HttpOverrides.current, isA<GostHttpOverrides>());
    });

    test('делегирует createHttpClient предыдущему оверрайду с нашим контекстом', () {
      final recorder = _RecordingOverrides();
      HttpOverrides.global = GostHttpOverrides(previous: recorder);

      final client = HttpClient();
      client.close();

      expect(recorder.createCalls, 1);
      expect(recorder.lastContext, isNotNull,
          reason: 'вместо null должен подставляться контекст с корнем Минцифры');
    });

    test('явно переданный контекст не подменяется', () {
      final recorder = _RecordingOverrides();
      HttpOverrides.global = GostHttpOverrides(previous: recorder);
      final own = SecurityContext();

      HttpClient(context: own).close();

      expect(recorder.lastContext, same(own));
    });

    test('делегирует findProxyFromEnvironment предыдущему оверрайду', () {
      final recorder = _RecordingOverrides();
      HttpOverrides.global = GostHttpOverrides(previous: recorder);

      final proxy = HttpOverrides.current!
          .findProxyFromEnvironment(Uri.parse('https://example.com'), null);

      expect(proxy, 'PROXY recorder:8888');
    });

    test('без previous — поведение по умолчанию', () {
      HttpOverrides.global = GostHttpOverrides();

      final proxy = HttpOverrides.current!
          .findProxyFromEnvironment(Uri.parse('https://example.com'), {});

      expect(proxy, 'DIRECT');
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

/// Оверрайд «как у хоста»: запоминает контекст и отдаёт свой прокси.
class _RecordingOverrides extends HttpOverrides {
  int createCalls = 0;
  SecurityContext? lastContext;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    createCalls++;
    lastContext = context;
    return super.createHttpClient(context);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    return 'PROXY recorder:8888';
  }
}
