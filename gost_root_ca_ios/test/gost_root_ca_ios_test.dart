import 'package:flutter_test/flutter_test.dart';
import 'package:gost_root_ca/gost_root_ca.dart';
import 'package:gost_root_ca_ios/gost_root_ca_ios.dart';

void main() {
  test('registerWith устанавливает платформенную реализацию', () {
    GostRootCaIos.registerWith();

    expect(GostRootCaPlatform.instance, isA<GostRootCaIos>());
  });
}
