import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Сайти DTEK закриті Incapsula: звичайний HTTP-запит отримує заглушку.
/// Тому відкриваємо сторінку в невидимому WebView — він проходить перевірку
/// як звичайний браузер — і виконуємо запити зсередини сторінки.
class DtekBridge {
  DtekBridge._();
  static final instance = DtekBridge._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  WebViewController? _controller;
  String? _url;
  bool _ready = false;
  final _pending = <int, Completer<dynamic>>{};
  var _seq = 0;
  Future<void> _queue = Future.value();

  WebViewController get controller => _controller ??= WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('SvitloBridge', onMessageReceived: _onMessage)
    ..setNavigationDelegate(NavigationDelegate(
      // Incapsula перезавантажує сторінку після перевірки — скидаємо готовність.
      onPageStarted: (_) => _ready = false,
    ));

  void _onMessage(JavaScriptMessage m) {
    final msg = jsonDecode(m.message) as Map<String, dynamic>;
    final c = _pending.remove(msg['id']);
    if (c == null || c.isCompleted) return;
    if (msg['ok'] == true) {
      c.complete(msg['data']);
    } else {
      c.completeError(Exception('${msg['data']}'));
    }
  }

  /// Виконує JS-вираз (можна Promise) на сторінці й повертає результат як JSON.
  Future<dynamic> _eval(String expr,
      {Duration timeout = const Duration(seconds: 20)}) {
    final id = ++_seq;
    final c = Completer<dynamic>();
    _pending[id] = c;
    controller.runJavaScript('''
(async () => {
  try {
    const r = await ($expr);
    SvitloBridge.postMessage(JSON.stringify({id: $id, ok: true, data: r === undefined ? null : r}));
  } catch (e) {
    SvitloBridge.postMessage(JSON.stringify({id: $id, ok: false, data: String(e && e.message || e)}));
  }
})();
''').catchError((Object e) {
      if (!c.isCompleted) c.completeError(e);
    });
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('сайт DTEK не відповідає');
    });
  }

  /// Операції по черзі: WebView один, а сторінки в різних регіонів різні.
  Future<T> _locked<T>(Future<T> Function() fn) {
    final result = _queue.then((_) => fn());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _open(String url, {bool reload = false}) async {
    if (!supported) throw UnsupportedError('невидимий браузер недоступний');
    if (_url == url && _ready && !reload) return;
    _url = url;
    _ready = false;
    await controller.loadRequest(Uri.parse(url));

    // Чекаємо, поки пройде перевірка Incapsula і на сторінці зʼявиться графік.
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        final ok = await _eval(
          "typeof DisconSchedule !== 'undefined' && !!DisconSchedule.fact && typeof \$ === 'function'",
          timeout: const Duration(seconds: 3),
        );
        if (ok == true) {
          _ready = true;
          return;
        }
      } catch (_) {
        // Сторінка ще вантажиться або перезавантажується.
      }
    }
    throw TimeoutException('сайт DTEK не завантажився');
  }

  /// { "м. Бровари": ["вул. ...", ...], ... }
  Future<Map<String, List<String>>> streets(String url) => _locked(() async {
        await _open(url);
        final raw = await _eval('DisconSchedule.streets || {}');
        return {
          for (final e in (raw as Map).entries)
            '${e.key}': [for (final s in (e.value as List)) '$s'],
        };
      });

  /// Будинки вулиці з чергою і поточним відключенням:
  /// { "12": {"sub_type_reason": ["GPV3.1"], "sub_type": "...", "start_date": "...", "end_date": "..."} }
  Future<Map<String, Map<String, dynamic>>> houses(
    String url,
    String city,
    String street,
  ) =>
      _locked(() async {
        await _open(url);
        final raw = await _eval('''
new Promise((resolve, reject) => {
  \$.post(document.querySelector('meta[name="ajaxUrl"]').content, {
    method: 'getHomeNum',
    data: [
      {name: 'city', value: ${jsonEncode(city)}},
      {name: 'street', value: ${jsonEncode(street)}},
      {name: 'updateFact', value: DisconSchedule.fact.update}
    ]
  }, a => a && a.result ? resolve(a.data || {}) : reject('DTEK не знайшов адресу'), 'JSON')
   .fail(e => reject('HTTP ' + e.status));
})''');
        return {
          for (final e in (raw as Map).entries)
            '${e.key}': Map<String, dynamic>.from(e.value as Map),
        };
      });

  /// Сирі DisconSchedule.fact і DisconSchedule.preset (свіже завантаження).
  Future<Map<String, dynamic>> schedule(String url) => _locked(() async {
        await _open(url, reload: true);
        final raw = await _eval(
            '({fact: DisconSchedule.fact, preset: DisconSchedule.preset})');
        return Map<String, dynamic>.from(raw as Map);
      });
}

/// Тримає невидимий WebView у дереві віджетів: на iOS і Android він має
/// бути «на екрані», щоб сторінка виконувалась. Розмір 1×1, майже прозорий.
class DtekBridgeHost extends StatelessWidget {
  const DtekBridgeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DtekBridge.supported) return child;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: WebViewWidget(controller: DtekBridge.instance.controller),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
