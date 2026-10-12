import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models.dart';

const _ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

/// Спільний HTTP-клієнт для сайтів обленерго.
class Net {
  Net._();

  static final http.Client client = http.Client();
  static http.Client? _withIntermediates;

  /// Деякі сервери обленерго (кабінет Черкасиобленерго, сайт
  /// Запоріжжяобленерго) віддають лише кінцевий сертифікат, без проміжного.
  /// Браузери догружають його самі, Dart — ні. Тому додаємо офіційні
  /// проміжні сертифікати Sectigo та Certum (взяті з AIA-адрес самих
  /// серверів): перевірка ланцюжка до системних коренів лишається чесною.
  static Future<http.Client> withIntermediates() async {
    if (_withIntermediates != null) return _withIntermediates!;
    final ctx = SecurityContext(withTrustedRoots: true);
    for (final f in const [
      'assets/certs/sectigo_dv_r36.pem',
      'assets/certs/certum_dv_tls_g2_r39.pem',
    ]) {
      final pem = await rootBundle.load(f);
      ctx.setTrustedCertificatesBytes(pem.buffer.asUint8List());
    }
    return _withIntermediates = IOClient(HttpClient(context: ctx));
  }

  static Map<String, String> headers([Map<String, String>? extra]) => {
        'User-Agent': _ua,
        'Accept-Language': 'uk-UA,uk;q=0.9',
        ...?extra,
      };

  static Future<http.Response> _check(Future<http.Response> f) async {
    final res = await f.timeout(const Duration(seconds: 25));
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode} ${res.request?.url.host}');
    }
    return res;
  }

  static Future<String> text(
    String url, {
    Map<String, String>? headers,
    bool cp1251 = false,
    http.Client? via,
  }) async {
    final res = await _check(
        (via ?? client).get(Uri.parse(url), headers: Net.headers(headers)));
    return cp1251
        ? decodeCp1251(res.bodyBytes)
        : utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  static Future<dynamic> json(
    String url, {
    Map<String, String>? headers,
    http.Client? via,
  }) async =>
      jsonDecode(await text(url, headers: headers, via: via));

  static Future<String> post(
    String url,
    Map<String, String> form, {
    Map<String, String>? headers,
    bool cp1251 = false,
  }) async {
    final res = await _check(client.post(
      Uri.parse(url),
      headers: Net.headers(headers),
      body: form,
      encoding: cp1251 ? latin1 : utf8,
    ));
    return cp1251
        ? decodeCp1251(res.bodyBytes)
        : utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}

// ---------------------------------------------------------------------------
// windows-1251 (сайт Житомиробленерго)

const _cp1251High =
    'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї'
    'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя';

String decodeCp1251(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.writeCharCode(b < 0x80 ? b : _cp1251High.codeUnitAt(b - 0x80));
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// HTML

final _tag = RegExp(r'<[^>]+>');
// Рядкові теги прибираємо без пробілу: на сайтах трапляється «10<span>:00».
final _inlineTag = RegExp(r'</?(span|b|strong|i|em|u|a|font|sup|sub)(\s[^>]*)?>', caseSensitive: false);
final _blockEnd = RegExp(r'</(p|div|li|h\d|tr|td|th|br)\s*>|<br\s*/?>', caseSensitive: false);
final _scripts = RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false);

String htmlUnescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&nbsp', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&rsquo;', '’')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));

/// HTML → текст із переносами рядків на місці блоків.
String htmlToText(String html) {
  final t = html
      .replaceAll(_scripts, ' ')
      .replaceAll(_blockEnd, '\n')
      .replaceAll(_inlineTag, '')
      .replaceAll(_tag, ' ');
  return htmlUnescape(t)
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

String cellText(String html) =>
    htmlUnescape(html.replaceAll(_inlineTag, '').replaceAll(_tag, ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Усі `<tr>` таблиці як списки сирих HTML-клітинок.
List<List<String>> tableRows(String tableHtml) => [
      for (final tr in RegExp(r'<tr[\s\S]*?</tr>', caseSensitive: false).allMatches(tableHtml))
        [
          for (final td in RegExp(r'<t[dh]([^>]*)>([\s\S]*?)</t[dh]>', caseSensitive: false)
              .allMatches(tr[0]!))
            td[0]!,
        ],
    ];

List<String> htmlTables(String html) => [
      for (final m in RegExp(r'<table[\s\S]*?</table>', caseSensitive: false).allMatches(html)) m[0]!,
    ];

// ---------------------------------------------------------------------------
// Дати та час (Київ)

int _kyivOffsetSeconds(int unix) =>
    toKyiv(unix).difference(DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true)).inSeconds;

/// Північ за Києвом для календарної дати, секунди Unix.
int kyivMidnight(int year, int month, int day) {
  final utc = DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ 1000;
  return utc - _kyivOffsetSeconds(utc - 3 * 3600);
}

int kyivToday([int? now]) {
  final t = toKyiv(now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);
  return kyivMidnight(t.year, t.month, t.day);
}

const _monthsGen = [
  'січня', 'лютого', 'березня', 'квітня', 'травня', 'червня',
  'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня',
];

/// Знаходить дату в тексті: «13 жовтня», «13.10.2026», «13-10-2026», «2026-10-13».
int? findKyivDate(String text, {int? now}) {
  final nowK = toKyiv(now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);
  var m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (m != null) return kyivMidnight(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  m = RegExp(r'(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})').firstMatch(text);
  if (m != null) return kyivMidnight(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  m = RegExp('(\\d{1,2})\\s+(${_monthsGen.join('|')})', caseSensitive: false).firstMatch(text);
  if (m != null) {
    final month = _monthsGen.indexOf(m[2]!.toLowerCase()) + 1;
    var year = nowK.year;
    // «1 січня», опубліковане в грудні, — це вже наступний рік.
    if (month < nowK.month - 6) year++;
    if (month > nowK.month + 6) year--;
    return kyivMidnight(year, month, int.parse(m[1]!));
  }
  return null;
}

/// "08:30" → 510 хвилин; "24:00" → 1440.
int? parseHm(String s) {
  final m = RegExp(r'(\d{1,2})\s*[:.]\s*(\d{2})').firstMatch(s);
  if (m == null) return null;
  return int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

// ---------------------------------------------------------------------------
// Інтервали → 48 слотів

class Span {
  final int from; // хвилини від початку доби
  final int to;
  final Power power;
  const Span(this.from, this.to, [this.power = Power.off]);
}

List<Power> slotsFromSpans(Iterable<Span> spans) {
  final slots = List.filled(48, Power.on);
  for (final s in spans) {
    var to = s.to <= s.from ? 1440 : s.to; // 22:00-00:00
    final a = (s.from ~/ 30).clamp(0, 48);
    final b = (to / 30).ceil().clamp(0, 48);
    for (var i = a; i < b; i++) {
      if (slots[i] != Power.off) slots[i] = s.power;
    }
  }
  return slots;
}

final _interval = RegExp(
  r'(\d{1,2}\s*[:.]\s*\d{2})\s*(?:-|–|—|до|по)\s*(\d{1,2}\s*[:.]\s*\d{2})',
  caseSensitive: false,
);

/// Усі інтервали «08:00-12:00», «з 08:00 до 10:00» у рядку.
List<Span> spansInText(String s, [Power power = Power.off]) => [
      for (final m in _interval.allMatches(s))
        Span(parseHm(m[1]!)!, parseHm(m[2]!)!, power),
    ];

final _queueAtStart = RegExp(
  r'^(?:[-•*]\s*)?(?:(?:група|черга|підчерга|гпв)\s*№?\s*)?(\d{1,2})[.,](\d)(?!\d)\s*[.:)\-–—]?\s*(.*)$',
  caseSensitive: false,
);

/// Розбирає текстові графіки обленерго:
///   «1.1 10:00 - 12:00, 18:00 - 20:00»
///   «Група 1.1. Електроенергії немає з 08:00 до 10:00.»
///   «2.2 не вимикається»
/// Повертає черга → проміжки без світла (порожній список — не вимикається).
Map<String, List<Span>> parseQueueLines(String text) {
  final result = <String, List<Span>>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final m = _queueAtStart.firstMatch(line);
    if (m == null) continue;
    final q = '${int.parse(m[1]!)}.${m[2]}';
    final rest = m[3]!;
    final maybe = RegExp(r'можлив', caseSensitive: false).hasMatch(rest);
    (result['GPV$q'] ??= []).addAll(spansInText(rest, maybe ? Power.maybe : Power.off));
  }
  return result;
}

/// Збирає RegionSchedule з «день → черга → проміжки».
RegionSchedule scheduleFromSpans(
  Map<int, Map<String, List<Span>>> byDay, {
  required String source,
  String updated = '',
  Map<String, String>? names,
}) {
  final days = <int, Map<String, DaySchedule>>{};
  final allQueues = <String>{};
  final today = kyivToday();
  byDay.forEach((day, queues) {
    // Старі графіки (сайт ще показує липневий) не показуємо.
    if (day < today) return;
    days[day] = {
      for (final e in queues.entries) e.key: DaySchedule(day, slotsFromSpans(e.value)),
    };
    allQueues.addAll(queues.keys);
  });
  final sorted = allQueues.toList()..sort(compareQueues);
  return RegionSchedule(
    queueNames: {
      for (final q in sorted) q: names?[q] ?? 'Черга ${queueShort(q)}',
    },
    days: days,
    updated: updated,
    today: kyivToday(),
    source: source,
  );
}

/// Стандартні підчерги 1.1 … 6.2.
const standardQueues = [
  'GPV1.1', 'GPV1.2', 'GPV2.1', 'GPV2.2', 'GPV3.1', 'GPV3.2',
  'GPV4.1', 'GPV4.2', 'GPV5.1', 'GPV5.2', 'GPV6.1', 'GPV6.2',
];

/// «3 черга 1 підчерга» / «підчерги: 6.1» / «3.1» → GPV3.1.
String? queueFromText(String text) {
  var m = RegExp(r'(\d+)\s*черг\w*\D{0,5}(\d+)\s*підчерг', caseSensitive: false).firstMatch(text);
  if (m != null) return 'GPV${int.parse(m[1]!)}.${int.parse(m[2]!)}';
  m = RegExp(r'(?<![\d.])(\d{1,2})\.(\d)(?![\d])').firstMatch(text);
  if (m != null) return 'GPV${int.parse(m[1]!)}.${m[2]}';
  return null;
}

/// Фільтр списку за підрядком без урахування регістру.
List<T> filterBy<T>(Iterable<T> items, String Function(T) label, String q) {
  final query = q.trim().toLowerCase();
  if (query.isEmpty) return items.toList();
  return items.where((i) => label(i).toLowerCase().contains(query)).toList();
}
