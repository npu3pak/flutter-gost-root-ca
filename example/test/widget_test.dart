import 'package:flutter_test/flutter_test.dart';

import 'package:gost_root_ca_example/main.dart';

void main() {
  testWidgets('меню рендерит все поверхности', (WidgetTester tester) async {
    await tester.pumpWidget(const GostRootCaExampleApp());

    expect(find.text('REST Flutter (dart:io HttpClient)'), findsOneWidget);
    expect(find.text('REST нативный (MethodChannel)'), findsOneWidget);
    expect(find.text('WebView Flutter (webview_flutter)'), findsOneWidget);
    expect(find.text('WebView нативный'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Изображение (Image.network)'),
      200,
    );
    expect(find.text('Изображение (Image.network)'), findsOneWidget);
  });
}
