import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gost_root_ca/gost_root_ca.dart';
import 'package:gost_root_ca/src/gost_http_overrides.dart';
import 'package:gost_root_ca/src/gost_root_ca_platform_interface.dart';

void main() {
  group('GostRootCa.enable', () {
    late MockGostRootCaPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockGostRootCaPlatform();
      GostRootCaPlatform.instance = mockPlatform;
    });

    tearDown(() {
      GostRootCaPlatform.instance = MethodChannelGostRootCa();
      HttpOverrides.global = null;
    });

    test('уже стоящий HttpOverrides становится previous, а не затирается', () async {
      final host = _HostOverrides();
      HttpOverrides.global = host;

      await GostRootCa.enable();

      final current = HttpOverrides.current;
      expect(current, isA<GostHttpOverrides>());
      expect((current as GostHttpOverrides).previous, same(host));
    });

    test('повторный enable() не наслаивает GostHttpOverrides сам на себя', () async {
      final host = _HostOverrides();
      HttpOverrides.global = host;

      await GostRootCa.enable();
      await GostRootCa.enable();

      final current = HttpOverrides.current as GostHttpOverrides;
      expect(current.previous, same(host));
    });

    test('без чужого оверрайда previous == null', () async {
      await GostRootCa.enable();

      expect((HttpOverrides.current as GostHttpOverrides).previous, isNull);
    });

    test('вызывает платформу с встроенным PEM по умолчанию', () async {
      await GostRootCa.enable();

      expect(mockPlatform.enableCallCount, 1);
      expect(mockPlatform.lastCertPem, GostRootCert.pem);
    });

    test('передаёт переопределённый PEM', () async {
      const customPem = 'CUSTOM_PEM';

      await GostRootCa.enable(certPem: customPem);

      expect(mockPlatform.lastCertPem, customPem);
    });
  });
}

class _HostOverrides extends HttpOverrides {}
