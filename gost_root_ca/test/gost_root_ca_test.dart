import 'package:flutter_test/flutter_test.dart';
import 'package:gost_root_ca/gost_root_ca.dart';
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
