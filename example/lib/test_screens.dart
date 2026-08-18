import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const kYandex = 'https://ya.ru';
const kSber = 'https://www.sberbank.ru/';
const kYandexImage =
    'https://avatars.mds.yandex.net/get-yapic/0/0-0/islands-retina-50';
const kSberImage =
    'https://esa-si-res.online.sberbank.ru/ESA/common/r-2.15/img/image_sber.png';

const _channelName = 'gost_root_ca_example/native_tls_test';
const _webViewStatusChannelName = 'gost_root_ca_example/native_webview_status';
const _channel = MethodChannel(_channelName);
const _webViewStatusChannel = EventChannel(_webViewStatusChannelName);

/// Нативная проверка URL (iOS URLSession / Android HttpURLConnection).
Future<String> nativeCheckUrl(String url) async {
  final result = await _channel.invokeMapMethod<Object?, Object?>(
    'checkUrl',
    {'url': url},
  );
  final success = result?['success'] == true;
  if (success) {
    return 'HTTP ${result?['statusCode']}';
  }
  return result?['error']?.toString() ?? 'Неизвестная ошибка';
}

/// Открывает нативный WebView поверх текущего экрана.
Future<void> openNativeWebView(String url) {
  return _channel.invokeMethod<void>('openNativeWebView', {'url': url});
}

/// Статусы загрузки нативного WebView.
Stream<Map<Object?, Object?>> nativeWebViewStatusStream() {
  return _webViewStatusChannel.receiveBroadcastStream().cast<Map<Object?, Object?>>();
}

enum TestStatus { loading, success, failure }

String _statusText(TestStatus status) {
  switch (status) {
    case TestStatus.loading:
      return 'ЗАГРУЗКА';
    case TestStatus.success:
      return 'УСПЕХ';
    case TestStatus.failure:
      return 'ОШИБКА';
  }
}

class TestPageScaffold extends StatelessWidget {
  final String title;
  final TestStatus status;
  final String? detail;
  final Widget body;

  const TestPageScaffold({
    super.key,
    required this.title,
    required this.status,
    required this.detail,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TestStatus.loading => Colors.grey.shade300,
      TestStatus.success => Colors.lightGreen.shade200,
      TestStatus.failure => Colors.red.shade200,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusText(status),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (detail != null) Text(detail!),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

// MARK: - REST Flutter (dart:io HttpClient)

class RestFlutterTestPage extends StatefulWidget {
  final String url;

  const RestFlutterTestPage({super.key, required this.url});

  @override
  State<RestFlutterTestPage> createState() => _RestFlutterTestPageState();
}

class _RestFlutterTestPageState extends State<RestFlutterTestPage> {
  var _status = TestStatus.loading;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _status = TestStatus.loading;
      _detail = 'Выполняется запрос…';
    });
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(widget.url));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      if (!mounted) return;
      setState(() {
        _status = TestStatus.success;
        _detail = 'HTTP ${response.statusCode}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = TestStatus.failure;
        _detail = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TestPageScaffold(
      title: 'REST Flutter',
      status: _status,
      detail: _detail,
      body: Center(child: Text(widget.url)),
    );
  }
}

// MARK: - REST нативный (MethodChannel)

class RestNativeTestPage extends StatefulWidget {
  final String url;

  const RestNativeTestPage({super.key, required this.url});

  @override
  State<RestNativeTestPage> createState() => _RestNativeTestPageState();
}

class _RestNativeTestPageState extends State<RestNativeTestPage> {
  var _status = TestStatus.loading;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _status = TestStatus.loading;
      _detail = 'Выполняется запрос…';
    });
    try {
      final detail = await nativeCheckUrl(widget.url);
      if (!mounted) return;
      setState(() {
        _status = detail.startsWith('HTTP') ? TestStatus.success : TestStatus.failure;
        _detail = detail;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = TestStatus.failure;
        _detail = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TestPageScaffold(
      title: 'REST нативный',
      status: _status,
      detail: _detail,
      body: Center(child: Text(widget.url)),
    );
  }
}

// MARK: - WebView Flutter (webview_flutter)

class WebViewFlutterTestPage extends StatefulWidget {
  final String url;

  const WebViewFlutterTestPage({super.key, required this.url});

  @override
  State<WebViewFlutterTestPage> createState() => _WebViewFlutterTestPageState();
}

class _WebViewFlutterTestPageState extends State<WebViewFlutterTestPage> {
  var _status = TestStatus.loading;
  String? _detail;
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_status != TestStatus.failure) {
              setState(() {
                _status = TestStatus.success;
                _detail = widget.url;
              });
            }
          },
          onWebResourceError: (error) {
            setState(() {
              _status = TestStatus.failure;
              _detail = '${error.errorCode} ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return TestPageScaffold(
      title: 'WebView Flutter',
      status: _status,
      detail: _detail,
      body: WebViewWidget(controller: _controller),
    );
  }
}

// MARK: - WebView нативный

class WebViewNativeTestPage extends StatefulWidget {
  final String url;

  const WebViewNativeTestPage({super.key, required this.url});

  @override
  State<WebViewNativeTestPage> createState() => _WebViewNativeTestPageState();
}

class _WebViewNativeTestPageState extends State<WebViewNativeTestPage> {
  var _status = TestStatus.loading;
  String? _detail = 'Ожидание открытия нативного экрана';
  StreamSubscription<Map<Object?, Object?>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = nativeWebViewStatusStream().listen((status) {
      if (!mounted) return;
      final event = status['event'];
      final success = event == 'load_finished';
      setState(() {
        _status = success ? TestStatus.success : TestStatus.failure;
        _detail = status['error']?.toString() ?? status['url']?.toString();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _status = TestStatus.loading;
      _detail = 'Открытие нативного экрана…';
    });
    try {
      await openNativeWebView(widget.url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = TestStatus.failure;
        _detail = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TestPageScaffold(
      title: 'WebView нативный',
      status: _status,
      detail: _detail,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.url, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _open,
                child: const Text('Открыть нативный WebView ещё раз'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: - Изображение (Image.network)

class ImageTestPage extends StatefulWidget {
  final String url;

  const ImageTestPage({super.key, required this.url});

  @override
  State<ImageTestPage> createState() => _ImageTestPageState();
}

class _ImageTestPageState extends State<ImageTestPage> {
  var _status = TestStatus.loading;
  String? _detail = 'Загрузка изображения…';

  @override
  Widget build(BuildContext context) {
    return TestPageScaffold(
      title: 'Изображение',
      status: _status,
      detail: _detail,
      body: Center(
        child: Image.network(
          widget.url,
          width: 300,
          height: 220,
          fit: BoxFit.contain,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _status = TestStatus.success;
                    _detail = widget.url;
                  });
                }
              });
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _status = TestStatus.failure;
                  _detail = 'Не удалось загрузить изображение';
                });
              }
            });
            return const Text('Ошибка загрузки изображения');
          },
        ),
      ),
    );
  }
}
