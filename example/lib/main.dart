import 'package:flutter/material.dart';
import 'package:gost_root_ca/gost_root_ca.dart';

import 'test_screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GostRootCa.enable();
  runApp(const GostRootCaExampleApp());
}

class GostRootCaExampleApp extends StatelessWidget {
  const GostRootCaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gost_root_ca example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const MenuPage(),
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('gost_root_ca · проверка TLS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'REST Flutter (dart:io HttpClient)',
              restFlutterTests(context)),
          _section(context, 'REST нативный (MethodChannel)',
              restNativeTests(context)),
          _section(context, 'WebView Flutter (webview_flutter)',
              webViewFlutterTests(context)),
          _section(context, 'WebView нативный', webViewNativeTests(context)),
          _section(context, 'Изображение (Image.network)',
              imageTests(context)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> buttons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        ...buttons,
      ],
    );
  }

  List<Widget> restFlutterTests(BuildContext context) => [
        _button(context, 'Яндекс', () => _open(context, RestFlutterTestPage(url: kYandex))),
        _button(context, 'Сбер', () => _open(context, RestFlutterTestPage(url: kSber))),
      ];

  List<Widget> restNativeTests(BuildContext context) => [
        _button(context, 'Яндекс', () => _open(context, RestNativeTestPage(url: kYandex))),
        _button(context, 'Сбер', () => _open(context, RestNativeTestPage(url: kSber))),
      ];

  List<Widget> webViewFlutterTests(BuildContext context) => [
        _button(context, 'Яндекс', () => _open(context, WebViewFlutterTestPage(url: kYandex))),
        _button(context, 'Сбер', () => _open(context, WebViewFlutterTestPage(url: kSber))),
      ];

  List<Widget> webViewNativeTests(BuildContext context) => [
        _button(context, 'Яндекс', () => _open(context, WebViewNativeTestPage(url: kYandex))),
        _button(context, 'Сбер', () => _open(context, WebViewNativeTestPage(url: kSber))),
      ];

  List<Widget> imageTests(BuildContext context) => [
        _button(context, 'Яндекс',
            () => _open(context, ImageTestPage(url: kYandexImage))),
        _button(context, 'Сбер',
            () => _open(context, ImageTestPage(url: kSberImage))),
      ];

  Widget _button(BuildContext context, String text, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(onPressed: onPressed, child: Text(text)),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}
