import 'package:gost_root_ca/gost_root_ca.dart';

/// Endorsed-реализация gost_root_ca для Android.
/// Доверие к корню Минцифры обеспечивается Network Security Config
/// из манифеста плагина, поэтому enable() — no-op.
class GostRootCaAndroid extends GostRootCaPlatform {
  /// Вызывается DartPluginRegistrant при старте приложения.
  static void registerWith() {
    GostRootCaPlatform.instance = GostRootCaAndroid();
  }

  @override
  Future<void> enable(String certPem) async {
    // Network Security Config уже в манифесте плагина.
  }
}
