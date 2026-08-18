import 'package:flutter_test/flutter_test.dart';
import 'package:gost_root_ca/gost_root_ca.dart';
import 'package:gost_root_ca_android/gost_root_ca_android.dart';

void main() {
  test('registerWith устанавливает платформенную реализацию', () {
    GostRootCaAndroid.registerWith();

    expect(GostRootCaPlatform.instance, isA<GostRootCaAndroid>());
  });
}
