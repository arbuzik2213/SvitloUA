import 'dart:convert';

import '../address.dart';
import '../models.dart';
import 'address_source.dart';
import 'common.dart';

/// Адреса є в базі обленерго, але не входить до жодної черги ГПВ
/// (критична інфраструктура тощо).
class NotInQueueException implements Exception {
  @override
  String toString() =>
      'Ця адреса не входить до черг погодинних відключень — за графіком її не вимикають.';
}

/// Сервіси конкретного обленерго.
abstract class RegionalProvider {
  /// Пошук черги за адресою (null — чергу обирають вручну).
  AddressSource? get address => null;

  /// Графік. Для областей без графіка не викликається.
  Future<RegionSchedule> schedule(SavedAddress a);

  /// Поточне відключення саме цього будинку.
  Future<String?> notice(SavedAddress a) async => null;

  /// Черги для ручного вибору.
  List<String> get manualQueues => standardQueues;
}

RegionalProvider? regionalProvider(String oblastId) => switch (oblastId) {
      'mykolaiv' => _Mykolaiv(),
      'cherkasy' => _Cherkasy(),
      'ternopil' => _PowerOn.ternopil(),
      'lviv' => _PowerOn.lviv(),
      'zhytomyr' => _Zhytomyr(),
      'chernivtsi' => _Chernivtsi(),
      'volyn' => _Volyn(),
      'sumy' => _Sumy(),
      'khmelnytskyi' => _Khmelnytskyi(),
      'kharkiv' => _Kharkiv(),
      'poltava' => _Poltava(),
      'rivne' => _Rivne(),
      'ivano-frankivsk' => _IvanoFrankivsk(),
      'zaporizhzhia' => _Zaporizhzhia(),
      'zakarpattia' => _Zakarpattia(),
      _ => null,
    };

/// Джерело адрес, що завантажує повні списки рівнів і фільтрує їх локально.
abstract class _ListSource extends AddressSource {
  final _cache = <String, List<AddressOption>>{};

  Future<List<AddressOption>> load(int level, List<AddressOption> chosen);

  @override
  bool get isLocal => true;

  @override
  Future<List<AddressOption>> options(
      int level, List<AddressOption> chosen, String q) async {
    final key = '$level|${chosen.map((o) => o.id).join('|')}';
    final all = _cache[key] ??= await load(level, chosen);
    if (levels[level].grid) return filterHouses(all, q);
    return sortByRelevance(filterBy(all, (o) => o.label, q), q)
        .take(200)
        .toList();
  }

  @override
  Future<String?> queue(List<AddressOption> chosen) async {
    final q = AddressSource.queueOf(chosen.last);
    if (q == 'NONE') throw NotInQueueException();
    return q;
  }
}

String _gpv(String q) => q.startsWith('GPV') ? q : 'GPV$q';

// ===========================================================================
// Миколаївобленерго — off.energy.mk.ua (JSON API)

class _Mykolaiv extends RegionalProvider {
  static const _b = 'https://off.energy.mk.ua/api';

  @override
  final AddressSource address = _MykolaivAddress();

  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final results = await Future.wait([
      Net.json('$_b/v2/schedule/active'),
      Net.json('$_b/outage-queue/by-type/3'),
      Net.json('$_b/schedule/time-series'),
    ]);
    final active = results[0] as List;
    final queues = {
      for (final q in results[1] as List) q['id'] as int: _gpv('${q['name']}'),
    };
    final slotOf = {
      for (final t in results[2] as List)
        t['id'] as int: (parseHm('${t['start']}') ?? 0) ~/ 30,
    };

    final byDay = <int, Map<String, List<Span>>>{};
    for (final s in active) {
      final day = findKyivDate('${s['from']}');
      if (day == null) continue;
      final m = byDay[day] ??= {for (final q in queues.values) q: <Span>[]};
      for (final e in (s['series'] as List? ?? const [])) {
        final q = queues[e['outage_queue_id']];
        final slot = slotOf[e['time_series_id']];
        if (q == null || slot == null) continue;
        final power = '${e['type']}' == 'PROBABLY_OFF' ? Power.maybe : Power.off;
        m[q]!.add(Span(slot * 30, slot * 30 + 30, power));
      }
    }
    return scheduleFromSpans(byDay, source: 'off.energy.mk.ua');
  }
}

class _MykolaivAddress extends _ListSource {
  static const _b = 'https://off.energy.mk.ua/api/addr';

  @override
  final levels = const [
    AddressLevel('Район', 'Дільниця або РЕМ'),
    cityLevel,
    streetLevel,
    houseLevel,
  ];

  @override
  Future<List<AddressOption>> load(int level, List<AddressOption> c) async {
    List<AddressOption> map(dynamic list, String id, String name) => [
          for (final o in list as List) AddressOption('${o[id]}', '${o[name]}'.trim()),
        ];
    switch (level) {
      case 0:
        return map(await Net.json('$_b/filii'), 'idfilial', 'fullname');
      case 1:
        return map(await Net.json('$_b/filii/${c[0].id}/ns'), 'idnaspunkt', 'naznaspunkt');
      case 2:
        return map(await Net.json('$_b/ns/${c[1].id}/street'), 'idstreet', 'nazstreet');
      default:
        return map(await Net.json('$_b/street/${c[2].id}/dom'), 'iddom', 'nazdom');
    }
  }

  @override
  Future<String?> queue(List<AddressOption> c) async {
    final list = await Net.json('$_b/dom/${c.last.id}/outage-queue') as List;
    for (final q in list) {
      final o = q['outage'];
      if (o is Map && o['type_id'] == 3) return _gpv('${o['name']}');
    }
    if (list.isEmpty) throw NotInQueueException();
    return null;
  }
}

// ===========================================================================
// Черкасиобленерго — кабінет (адреса → особовий рахунок → черга) і новини

class _Cherkasy extends RegionalProvider {
  @override
  final AddressSource address = _CherkasyAddress();

  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    const base = 'https://www.cherkasyoblenergo.com/api/v1/posts';
    final list = await Net.json('$base/category/news?lang=uk&page=0&size=20');
    final posts = ((list['data'] ?? const {})['content'] as List? ?? const [])
        .where((p) => RegExp(r'погодинних відключень|ГПВ', caseSensitive: false)
            .hasMatch('${p['title']}'))
        .toList();

    final today = kyivToday();
    final byDay = <int, Map<String, List<Span>>>{};
    var updated = '';
    // Новини йдуть від нових до старих: перший пост на дату — актуальний.
    for (final p in posts.take(6)) {
      final day = findKyivDate('${p['title']}');
      if (day == null || day < today || byDay.containsKey(day)) continue;
      final post = await Net.json('$base/${p['slug']}?lang=uk');
      final text = htmlToText('${post['data']?['content'] ?? ''}');
      final queues = parseQueueLines(text);
      if (queues.isEmpty) continue;
      byDay[day] = {for (final q in standardQueues) q: queues[q] ?? <Span>[]};
      if (updated.isEmpty) updated = '${p['publishedAt'] ?? ''}'.replaceFirst('T', ' ');
    }
    return scheduleFromSpans(byDay, source: 'cherkasyoblenergo.com', updated: updated);
  }
}

class _CherkasyAddress extends _ListSource {
  static const _cab = 'https://cabinet.cherkasyoblenergo.com/api_new/disconn.php';

  Future<dynamic> _op(Map<String, String> p) async => Net.json(
        Uri.parse(_cab).replace(queryParameters: p).toString(),
        via: await Net.withIntermediates(),
      );

  @override
  final levels = const [
    AddressLevel('Філія', 'Філія або РЕМ'),
    cityLevel,
    streetLevel,
    houseLevel,
  ];

  @override
  Future<List<AddressOption>> load(int level, List<AddressOption> c) async {
    List<AddressOption> idName(dynamic l) => [
          for (final o in (l is List ? l : const []))
            AddressOption('${o['ID']}', '${o['NAME']}'.trim()),
        ];
    switch (level) {
      case 0:
        return idName(await _op({'op': 'department_list'}));
      case 1:
        return idName(await _op({'op': 'city_list', 'dept_id': c[0].id}));
      case 2:
        return idName(await _op({'op': 'street_list', 'city_id': c[1].id, 'search_name': ''}));
      default:
        final l = await _op({'op': 'house_list', 'street_id': c[2].id, 'search_name': ''});
        return [
          for (final o in (l is List ? l : const []))
            AddressOption('${o['HOUSE']}', '${o['HOUSE']}'),
        ];
    }
  }

  @override
  Future<String?> queue(List<AddressOption> c) async {
    final accounts = await _op({'op': 'ls_list_by_addr', 'street_id': c[2].id, 'house': c[3].id});
    if (accounts is! List || accounts.isEmpty) return null;
    final d = toKyiv(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    var notIncluded = false;
    // Кілька рахунків на будинок (квартири): беремо перший, що має чергу.
    for (final acc in accounts.take(3)) {
      final r = await _op({
        'op': 'disconn_by_ls',
        'abon_ls': '${acc['LS']}',
        'disconn_selector': '2',
        'n_date': date,
        'k_date': date,
      });
      for (final q in (r is Map ? r['DISCONN_QUEUQ'] as List? ?? const [] : const [])) {
        final info = '${q['QUEUE_INFO']}';
        if (!info.toLowerCase().contains('погодин')) continue;
        if (info.contains('не включено')) {
          notIncluded = true;
          continue;
        }
        final queue = queueFromText(info);
        if (queue != null) return queue;
      }
    }
    if (notIncluded) throw NotInQueueException();
    return null;
  }
}

// ===========================================================================
// PowerOn: Тернопільобленерго і Львівобленерго (однакова платформа)

class _PowerOn extends RegionalProvider {
  _PowerOn.ternopil()
      : addrApi = 'https://api-poweron.toe.com.ua/api',
        origin = 'https://poweron.toe.com.ua',
        lviv = false;
  _PowerOn.lviv()
      : addrApi = 'https://power-api.loe.lviv.ua/api',
        origin = 'https://poweron.loe.lviv.ua',
        lviv = true;

  final String addrApi;
  final String origin;
  final bool lviv;

  Map<String, String> get headers => {
        'Accept': 'application/ld+json',
        'Origin': origin,
        'Referer': '$origin/',
      };

  @override
  late final AddressSource address = _PowerOnAddress(this);

  @override
  Future<RegionSchedule> schedule(SavedAddress a) =>
      lviv ? _lvivSchedule() : _ternopilSchedule(a);

  /// Львів: графік текстом у меню «photo-grafic» (Today / Tomorrow).
  Future<RegionSchedule> _lvivSchedule() async {
    final d = await Net.json('https://api.loe.lviv.ua/api/menus?page=1&type=photo-grafic',
        headers: headers);
    final items = ((d['hydra:member'] as List?)?.firstOrNull?['menuItems'] as List?) ?? const [];
    final today = kyivToday();
    final byDay = <int, Map<String, List<Span>>>{};
    for (final it in items) {
      final name = '${it['name']}'.toLowerCase();
      if (name != 'today' && name != 'tomorrow') continue;
      final text = htmlToText('${it['rawHtml'] ?? ''}');
      final queues = parseQueueLines(text);
      if (queues.isEmpty) continue;
      final day = findKyivDate(text) ?? (name == 'today' ? today : today + 86400);
      byDay[day] = {for (final q in standardQueues) q: queues[q] ?? <Span>[]};
    }
    return scheduleFromSpans(byDay, source: 'poweron.loe.lviv.ua');
  }

  /// Тернопіль: графік по черзі будинку (потрібні city.id і street.id).
  Future<RegionSchedule> _ternopilSchedule(SavedAddress a) async {
    if (a.path.length < 3) throw Exception('немає адреси');
    final city = a.path[0].id, street = a.path[1].id;
    final q = queueShort(a.queue);
    final now = DateTime.now().toUtc();
    String iso(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}T00:00:00Z';
    final day0 = DateTime.utc(now.year, now.month, now.day);
    final url = Uri.parse('$addrApi/a_gpv_g').replace(queryParameters: {
      'after': iso(day0),
      'before': iso(day0.add(const Duration(days: 2))),
      'group[]': q,
      'time': '$city$street',
    });
    final d = await Net.json(url.toString(), headers: {
      ...headers,
      'x-debug-key': base64.encode(utf8.encode('$city/$street')),
    });
    final byDay = <int, Map<String, List<Span>>>{};
    for (final m in (d['hydra:member'] as List? ?? const [])) {
      final day = findKyivDate('${m['dateGraph']}');
      final times = (m['dataJson']?[q]?['times']) as Map?;
      if (day == null || times == null || times.isEmpty) continue;
      final spans = <Span>[];
      times.forEach((k, v) {
        final start = parseHm('$k');
        if (start == null) return;
        if ('$v' == '1') spans.add(Span(start, start + 30));
        if ('$v' == '10') spans.add(Span(start, start + 30, Power.maybe));
      });
      byDay[day] = {a.queue: spans};
    }
    return scheduleFromSpans(byDay, source: 'poweron.toe.com.ua');
  }
}

class _PowerOnAddress extends AddressSource {
  _PowerOnAddress(this.p);
  final _PowerOn p;
  final _streets = <String, List<AddressOption>>{};

  @override
  final levels = const [
    AddressLevel('Населений пункт', 'Назва міста чи села', minQuery: 2),
    streetLevel,
    houseLevel,
  ];

  List<dynamic> _members(dynamic d) => (d is Map ? d['hydra:member'] as List? : null) ?? const [];

  @override
  Future<List<AddressOption>> options(int level, List<AddressOption> c, String q) async {
    switch (level) {
      case 0:
        final d = await Net.json(
            '${p.addrApi}/pw_cities?pagination=false&name=${Uri.encodeQueryComponent(q.trim())}',
            headers: p.headers);
        return sortByRelevance([
          for (final o in _members(d))
            if ('${o['name']}'.trim().isNotEmpty)
              AddressOption('${o['id']}', '${o['name']}',
                  {'otg': o['otg'] is Map ? '${o['otg']['name']}' : ''}),
        ], q);
      case 1:
        final all = _streets[c[0].id] ??= [
          for (final o in _members(await Net.json(
              '${p.addrApi}/pw_streets?pagination=false&city.id=${c[0].id}',
              headers: p.headers)))
            if ('${o['name']}'.trim().isNotEmpty)
              AddressOption('${o['id']}', '${o['name']}'.trim()),
        ];
        return sortByRelevance(filterBy(all, (o) => o.label, q), q).take(200).toList();
      default:
        return filterHouses(await _houses(c[0].id, c[1].id), q);
    }
  }

  Future<List<AddressOption>> _houses(String city, String street) async {
    final rows = p.lviv
        ? _members(await Net.json(
            '${p.addrApi}/pw_accounts?pagination=false&city.id=$city&street.id=$street',
            headers: p.headers))
        : ((await Net.json(
                    '${p.addrApi}/pw-accounts/building-names?cityId=$city&streetId=$street',
                    headers: p.headers))['buildingNames'] as List? ??
            const []);
    final byName = <String, AddressOption>{};
    for (final r in rows) {
      final name = '${r['buildingName'] ?? ''}'.trim();
      if (name.isEmpty || byName.containsKey(name)) continue;
      var g = '${r['chergGpv'] ?? ''}'.trim();
      if (RegExp(r'^\d\d$').hasMatch(g)) g = '${g[0]}.${g[1]}'; // "21" → "2.1"
      byName[name] = AddressOption(name, name, {
        'queue': RegExp(r'^\d+\.\d$').hasMatch(g) ? _gpv(g) : 'NONE',
      });
    }
    return byName.values.toList();
  }

  @override
  Future<String?> queue(List<AddressOption> c) async {
    final q = AddressSource.queueOf(c.last);
    if (q == 'NONE') throw NotInQueueException();
    return q;
  }
}

// ===========================================================================
// Житомиробленерго — HTML-форми у windows-1251

class _Zhytomyr extends RegionalProvider {
  static const url = 'https://www.ztoe.com.ua/unhooking-search.php';

  @override
  final AddressSource address = _ZhytomyrAddress();

  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final html = await Net.text(url, cp1251: true);
    final byDay = <int, Map<String, List<Span>>>{};
    for (final t in htmlTables(html).where((t) => t.contains('00:00-00:30'))) {
      final rows = tableRows(t);
      int? day;
      final queues = <String, List<Span>>{};
      for (final row in rows) {
        final texts = row.map(cellText).toList();
        day ??= texts.map((s) => findKyivDate(s)).whereType<int>().firstOrNull;
        final qi = texts.indexWhere((s) => RegExp(r'^\d\.\d$').hasMatch(s));
        if (qi < 0 || row.length < 48) continue;
        final slots = row.sublist(row.length - 48);
        final spans = <Span>[];
        for (var i = 0; i < 48; i++) {
          if (slots[i].toLowerCase().contains('ff3333')) spans.add(Span(i * 30, i * 30 + 30));
        }
        queues[_gpv(texts[qi])] = spans;
      }
      if (day != null && queues.isNotEmpty) byDay[day] = queues;
    }
    return scheduleFromSpans(byDay, source: 'ztoe.com.ua');
  }
}

class _ZhytomyrAddress extends _ListSource {
  @override
  final levels = const [
    AddressLevel('Район', 'РЕМ'),
    cityLevel,
    streetLevel,
    houseLevel,
  ];

  static List<AddressOption> _select(String html, String name) {
    final m = RegExp('<select[^>]*name="$name"[^>]*>([\\s\\S]*?)</select>').firstMatch(html);
    if (m == null) return const [];
    return [
      for (final o in RegExp(r'<option[^>]*value="([^"]*)"[^>]*>([^<]*)').allMatches(m[1]!))
        if (o[1] != '0' && o[1]!.isNotEmpty) AddressOption(o[1]!, cellText(o[2]!)),
    ];
  }

  @override
  Future<List<AddressOption>> load(int level, List<AddressOption> c) async {
    const url = _Zhytomyr.url;
    switch (level) {
      case 0:
        return _select(await Net.text(url, cp1251: true), 'rem_id');
      case 1:
        return _select(await Net.post(url, {'rem_id': c[0].id}, cp1251: true), 'naspunkt_id');
      case 2:
        return _select(
            await Net.post(url, {'rem_id': c[0].id, 'naspunkt_id': c[1].id}, cp1251: true),
            'vulica_id');
      default:
        final html = await Net.post(
            url, {'rem_id': c[0].id, 'naspunkt_id': c[1].id, 'vulica_id': c[2].id},
            cp1251: true);
        final houses = <String, AddressOption>{};
        for (final t in htmlTables(html).where((t) => t.contains('Будинки'))) {
          for (final row in tableRows(t)) {
            final cells = row.map(cellText).toList();
            if (cells.length < 6 || cells[3] == 'Будинки') continue;
            final household = !cells.last.toLowerCase().contains('непобут');
            final q = RegExp(r'^\d+$').hasMatch(cells[4]) && RegExp(r'^\d+$').hasMatch(cells[5])
                ? 'GPV${cells[4]}.${cells[5]}'
                : 'NONE';
            for (final h in cells[3].split(',')) {
              final house = h.trim();
              if (house.isEmpty) continue;
              // Побутові споживачі мають пріоритет над непобутовими в тому ж будинку.
              if (houses.containsKey(house) && !household) continue;
              houses[house] = AddressOption(house, house, {'queue': q});
            }
          }
        }
        return houses.values.toList();
    }
  }
}

// ===========================================================================
// Чернівціобленерго — 12 груп; адреси — великі HTML-таблиці по дільницях

class _Chernivtsi extends RegionalProvider {
  @override
  final AddressSource address = _ChernivtsiAddress();

  @override
  List<String> get manualQueues => [for (var i = 1; i <= 12; i++) 'GPV$i'];

  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final byDay = <int, Map<String, List<Span>>>{};
    for (final url in const [
      'https://oblenergo.cv.ua/shutdowns/',
      'https://oblenergo.cv.ua/shutdowns/?next',
    ]) {
      final html = await Net.text(url);
      final gsv = html.indexOf('id="gsv"');
      if (gsv < 0) continue;
      final head = RegExp(r'<p>\s*(\d{2}\.\d{2}\.\d{4})').firstMatch(html.substring(gsv));
      final day = head == null ? null : findKyivDate(head[1]!);
      if (day == null || byDay.containsKey(day)) continue;
      final queues = <String, List<Span>>{};
      for (final m in RegExp(r'<div id="inf(\d+)"[^>]*>([\s\S]*?)</div>').allMatches(html)) {
        final cells = RegExp(r'<u>([^<]*)</u>').allMatches(m[2]!).map((u) => u[1]!.trim()).toList();
        if (cells.length < 48) continue;
        final spans = <Span>[];
        for (var i = 0; i < 48; i++) {
          final v = cells[i].toLowerCase();
          if (v == 'в') spans.add(Span(i * 30, i * 30 + 30));
          if (v == 'мз') spans.add(Span(i * 30, i * 30 + 30, Power.maybe));
        }
        queues['GPV${m[1]}'] = spans;
      }
      if (queues.isNotEmpty) byDay[day] = queues;
    }
    return scheduleFromSpans(byDay,
        source: 'oblenergo.cv.ua',
        names: {for (var i = 1; i <= 12; i++) 'GPV$i': 'Група $i'});
  }
}

class _ChernivtsiAddress extends _ListSource {
  /// дільниця → населений пункт → вулиця → будинок → група
  final _tree = <String, Map<String, Map<String, Map<String, String>>>>{};

  @override
  final levels = const [
    AddressLevel('Дільниця', 'Дільниця'),
    cityLevel,
    streetLevel,
    houseLevel,
  ];

  @override
  String get loadingHint => 'Завантажуємо адреси з сайту Чернівціобленерго…';

  Future<Map<String, Map<String, Map<String, String>>>> _district(String id) async {
    if (_tree[id] != null) return _tree[id]!;
    final html = await Net.text('https://oblenergo.cv.ua/shutdowns-search/$id/');
    final tree = <String, Map<String, Map<String, String>>>{};
    final city = html.contains('id="city_tbl"');
    for (final m in RegExp(r'<div>(?:<s>([^<]*)</s>)?<p>([^<]*)</p><b>([^<]*)</b><u>([^<]*)</u></div>')
        .allMatches(html)) {
      final place = city ? 'м. Чернівці' : cellText(m[1] ?? '');
      final street = cellText(m[2]!);
      final house = cellText(m[3]!).replaceFirst(RegExp(r'^буд\.\s*'), '');
      final group = m[4]!.trim();
      if (place.isEmpty || !RegExp(r'^\d+$').hasMatch(group)) continue;
      ((tree[place] ??= {})[street] ??= {})[house] = 'GPV$group';
    }
    return _tree[id] = tree;
  }

  @override
  Future<List<AddressOption>> load(int level, List<AddressOption> c) async {
    if (level == 0) {
      final html = await Net.text('https://oblenergo.cv.ua/shutdowns-search/');
      final sel = RegExp(r'<select[^>]*name="diln"[^>]*>([\s\S]*?)</select>').firstMatch(html);
      return [
        for (final o in RegExp(r'<option[^>]*value="(\d+)"[^>]*>([^<]*)').allMatches(sel?[1] ?? ''))
          if (o[1] != '0') AddressOption(o[1]!, cellText(o[2]!)),
      ];
    }
    final tree = await _district(c[0].id);
    switch (level) {
      case 1:
        return [for (final p in tree.keys) AddressOption(p, p)];
      case 2:
        return [for (final s in (tree[c[1].id] ?? const {}).keys) AddressOption(s, s)];
      default:
        return [
          for (final e in (tree[c[1].id]?[c[2].id] ?? const <String, String>{}).entries)
            AddressOption(e.key, e.key, {'queue': e.value}),
        ];
    }
  }
}

// ===========================================================================
// Волиньобленерго — пошук за назвами міста й вулиці (без підказок)

class _Volyn extends RegionalProvider {
  static const _base = 'https://energy.volyn.ua/spozhyvacham/perervy-u-elektropostachanni';

  @override
  final AddressSource address = _VolynAddress();

  static String _bare(String s) => s
      .replaceFirst(RegExp(r'^(м\.|місто|с\.|смт|село|вул\.|вулиця|пров\.|просп\.)\s*', caseSensitive: false), '')
      .trim();

  /// Графік на дати з форми, для конкретної адреси.
  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    if (a.path.length < 3) throw Exception('немає адреси');
    final page = await Net.text('$_base/hrafik-vidkliuchen/');
    final dates = RegExp(r'<option[^>]*value="(\d{4}-\d{2}-\d{2})"')
        .allMatches(page)
        .map((m) => m[1]!)
        .toSet();
    final house = a.path.last.label.toLowerCase();
    final byDay = <int, Map<String, List<Span>>>{};
    for (final date in dates) {
      final html = await Net.post('$_base/hrafik-vidkliuchen/pagephp.php', {
        'formGpvDate': date,
        'formCity': _bare(a.path[0].label),
        'formStreet': _bare(a.path[1].label),
        'searchForm': 'searchFromForm',
      });
      final spans = <Span>[];
      final tables = htmlTables(html);
      // Немає таблиці — графік на цю дату не опубліковано.
      if (tables.isEmpty) continue;
      for (final t in tables) {
        for (final row in tableRows(t)) {
          final text = row.map(cellText).join(' | ');
          final matchesHouse = RegExp('(^|[ ,|])${RegExp.escape(house)}([ ,|]|\$)', caseSensitive: false)
                  .hasMatch(text.toLowerCase()) ||
              text.contains(queueShort(a.queue));
          if (matchesHouse) spans.addAll(spansInText(text));
        }
      }
      final day = findKyivDate(date)!;
      byDay[day] = {a.queue: spans};
    }
    return scheduleFromSpans(byDay, source: 'energy.volyn.ua');
  }
}

class _VolynAddress extends AddressSource {
  @override
  final levels = const [
    AddressLevel('Населений пункт', 'Назва без «м.» чи «с.»', minQuery: 2, freeText: true),
    AddressLevel('Вулиця', 'Назва без «вул.»', minQuery: 2, freeText: true),
    houseLevel,
  ];

  final _cache = <String, List<AddressOption>>{};

  @override
  Future<List<AddressOption>> options(int level, List<AddressOption> c, String q) async {
    if (level < 2) {
      final v = q.trim();
      return v.length < 2 ? const [] : [AddressOption(v, v)];
    }
    final key = '${c[0].id}|${c[1].id}';
    final all = _cache[key] ??= await _load(c[0].id, c[1].id);
    return filterHouses(all, q);
  }

  Future<List<AddressOption>> _load(String city, String street) async {
    final html = await Net.post('${_Volyn._base}/cherga/', {
      'formCity': _Volyn._bare(city),
      'formStreet': _Volyn._bare(street),
    });
    final rows = <List<String>>[];
    for (final t in htmlTables(html).where((t) => t.contains('Черга у ГПВ'))) {
      rows.addAll(tableRows(t).map((r) => r.map(cellText).toList()).where((r) => r.length >= 5 && r[0] != 'Район'));
    }
    final streets = rows.map((r) => '${r[1]}, ${r[2]}').toSet();
    final out = <String, AddressOption>{};
    for (final r in rows) {
      final q = RegExp(r'^\d+\.\d$').hasMatch(r[4]) ? _gpv(r[4]) : 'NONE';
      for (final h in r[3].split(',')) {
        final house = h.trim();
        if (house.isEmpty) continue;
        final label = streets.length > 1 ? '${r[2]}, $house' : house;
        out.putIfAbsent(label, () => AddressOption(label, label, {'queue': q}));
      }
    }
    return out.values.toList();
  }

  @override
  Future<String?> queue(List<AddressOption> c) async {
    final q = AddressSource.queueOf(c.last);
    if (q == 'NONE') throw NotInQueueException();
    return q;
  }
}

// ===========================================================================
// Сумиобленерго — JSON API сайту

class _Sumy extends RegionalProvider {
  static const _b = 'https://www.soe.com.ua/api/vidkluchenya';

  @override
  final AddressSource address = _SumyAddress();

  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final d = await Net.json('$_b/get_all_data_disconnections_api');
    final queues = <String, List<Span>>{};
    var updated = '';
    for (final q in (d['data'] as List? ?? const [])) {
      if (q['no_data'] == true) continue;
      queues[_gpv('${q['cherga_n']}')] = [
        for (final t in (q['lst_time_disc'] as List? ?? const []))
          Span(parseHm('${t['start_time']}') ?? 0, parseHm('${t['end_time']}') ?? 0),
      ];
      updated = '${q['last_update'] ?? ''}'.replaceFirst('Оновлено: ', '');
    }
    return scheduleFromSpans(
      queues.isEmpty ? {} : {kyivToday(): queues},
      source: 'soe.com.ua',
      updated: updated,
    );
  }
}

class _SumyAddress extends AddressSource {
  static const _b = _Sumy._b;

  @override
  final levels = const [
    AddressLevel('Населений пункт', 'Назва міста чи села', minQuery: 2),
    AddressLevel('Вулиця', 'Назва вулиці', minQuery: 2),
    houseLevel,
  ];

  final _houses = <String, List<AddressOption>>{};

  List<dynamic> _list(dynamic d) {
    final data = d is Map ? d['data'] : null;
    return (data is Map ? data['list'] as List? : null) ?? const [];
  }

  @override
  Future<List<AddressOption>> options(int level, List<AddressOption> c, String q) async {
    final query = Uri.encodeQueryComponent(q.trim());
    switch (level) {
      case 0:
        return sortByRelevance([
          for (final r in _list(await Net.json('$_b/readCity?input=$query')))
            AddressOption('${r[0]}', '${r[1]}'),
        ], q);
      case 1:
        return [
          for (final r in _list(await Net.json('$_b/readStreet?input=$query&cityId=${c[0].id}')))
            AddressOption('${r[0]}', '${r[1]}'),
        ];
      default:
        final all = _houses[c[1].id] ??= [
          for (final r in _list(await Net.json('$_b/readHouseAndQnum?streetid=${c[1].id}')))
            AddressOption('${r[2]}', '${r[2]}', {
              // Сайт показує ГПВ з позиції 3 масиву черг.
              'queue': (r[3] is List && (r[3] as List).length > 3 && r[3][3] != null)
                  ? queueFromText('${r[3][3]}')
                  : null,
            }),
        ];
        return filterHouses(all, q);
    }
  }

  @override
  Future<String?> queue(List<AddressOption> c) async => AddressSource.queueOf(c.last);
}

// ===========================================================================
// Хмельницькобленерго — черга за адресою і поточні відключення (графіка немає)

class _Khmelnytskyi extends RegionalProvider {
  static const _b = 'https://hoe.com.ua';
  static const _xhr = {'X-Requested-With': 'XMLHttpRequest'};

  @override
  final AddressSource address = _KhmelnytskyiAddress();

  @override
  Future<RegionSchedule> schedule(SavedAddress a) =>
      throw UnsupportedError('Хмельницькобленерго не публікує графік');

  @override
  Future<String?> notice(SavedAddress a) async {
    if (a.path.length < 3) return null;
    final html = await Net.post('$_b/shutdown-events',
        {'streetId': a.path[1].id, 'house': a.path.last.id},
        headers: _xhr);
    final text = htmlToText(html);
    if (text.contains('відсутнє зареєстроване відключення')) return null;
    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  }
}

class _KhmelnytskyiAddress extends AddressSource {
  static const _b = _Khmelnytskyi._b;

  @override
  final levels = const [
    AddressLevel('Населений пункт', 'Назва міста чи села', minQuery: 2),
    AddressLevel('Вулиця', 'Назва вулиці', minQuery: 2),
    houseLevel,
  ];

  @override
  Future<List<AddressOption>> options(int level, List<AddressOption> c, String q) async {
    final t = Uri.encodeQueryComponent(q.trim());
    switch (level) {
      case 0:
        final d = await Net.json('$_b/settlements/?term=$t&_type=query&q=$t', headers: _Khmelnytskyi._xhr);
        return sortByRelevance([for (final o in d as List) AddressOption('${o['id']}', '${o['text']}')], q);
      case 1:
        final d = await Net.json('$_b/streets/${c[0].id}?term=$t&_type=query&q=$t', headers: _Khmelnytskyi._xhr);
        return [for (final o in d as List) AddressOption('${o['id']}', '${o['text']}')];
      default:
        final d = await Net.json('$_b/houses/${c[1].id}', headers: _Khmelnytskyi._xhr);
        return filterHouses([for (final h in d as List) AddressOption('$h', '$h')], q);
    }
  }

  @override
  Future<String?> queue(List<AddressOption> c) async {
    final html = await Net.post('$_b/shutdown-queues', {'streetId': c[1].id, 'house': c.last.id},
        headers: _Khmelnytskyi._xhr);
    final text = htmlToText(html);
    final line = text.split('\n').firstWhere((l) => l.contains('погодинних'), orElse: () => '');
    final q = queueFromText(line.substring(line.indexOf('(ГПВ)') + 1));
    if (q == null && line.isEmpty) throw NotInQueueException();
    return q;
  }
}

// ===========================================================================
// Області з ручним вибором черги: графік із сайту, черга — з офіційного списку

/// Харківобленерго: новини «…13 жовтня діятимуть … погодинних відключень».
class _Kharkiv extends RegionalProvider {
  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    const base = 'https://oblenergo.kharkiv.ua';
    final home = await Net.text('$base/uk');
    final links = RegExp(r'href="(/uk/node/\d+)"[^>]*>([^<]*погодинн[^<]*)<')
        .allMatches(home)
        .map((m) => (m[1]!, htmlUnescape(m[2]!)))
        .toList();
    final today = kyivToday();
    final byDay = <int, Map<String, List<Span>>>{};
    for (final (href, title) in links.take(5)) {
      final day = findKyivDate(title);
      if (day == null || day < today || byDay.containsKey(day)) continue;
      final html = await Net.text('$base$href');
      final art = RegExp(r'<article[\s\S]*?</article>').firstMatch(html)?[0] ?? html;
      final queues = parseQueueLines(htmlToText(art));
      if (queues.isEmpty) continue;
      byDay[day] = {for (final q in standardQueues) q: queues[q] ?? <Span>[]};
    }
    return scheduleFromSpans(byDay, source: 'oblenergo.kharkiv.ua');
  }
}

/// Полтаваобленерго: HTML-таблиця підчерг × 48 півгодин.
class _Poltava extends RegionalProvider {
  static const _b = 'https://www.poe.pl.ua/customs';
  static const _xhr = {'X-Requested-With': 'XMLHttpRequest'};

  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final byDay = <int, Map<String, List<Span>>>{};
    void parse(String html) {
      final day = findKyivDate(htmlToText(html.split('<table').first));
      if (day == null || !html.contains('turnoff-scheduleui-table')) return;
      final queues = <String, List<Span>>{};
      String? queue;
      for (final row in tableRows(html)) {
        for (final c in row) {
          final q = RegExp(r'table-queue[^>]*>\s*(\d+)').firstMatch(c);
          if (q != null) queue = q[1];
        }
        final sub = row.map((c) => RegExp(r'table-subqueue[^>]*>\s*(\d)').firstMatch(c)?[1]).whereType<String>().firstOrNull;
        if (queue == null || sub == null) continue;
        final cells = row.where((c) => c.contains('light_')).toList();
        if (cells.length < 48) continue;
        final spans = <Span>[];
        for (var i = 0; i < 48; i++) {
          if (cells[i].contains('light_2')) spans.add(Span(i * 30, i * 30 + 30));
          if (cells[i].contains('light_3')) spans.add(Span(i * 30, i * 30 + 30, Power.maybe));
        }
        queues['GPV$queue.$sub'] = spans;
      }
      if (queues.isNotEmpty) byDay[day] = queues;
    }

    parse(await Net.text('$_b/dynamicgpv-info.php', headers: _xhr));
    final t = toKyiv(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400);
    final tomorrow = '${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}-${t.year}';
    try {
      parse(await Net.post('$_b/newgpv-info.php',
          {'seldate': jsonEncode({'date_in': tomorrow})},
          headers: _xhr));
    } catch (_) {
      // Графіка на завтра ще може не бути.
    }
    return scheduleFromSpans(byDay, source: 'poe.pl.ua');
  }
}

/// Рівнеобленерго: таблиця «дата × підчерга» з інтервалами в клітинках.
class _Rivne extends RegionalProvider {
  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final html = await Net.text('https://www.roe.vsei.ua/disconnections');
    final byDay = <int, Map<String, List<Span>>>{};
    for (final t in htmlTables(html).where((t) => t.contains('Підчерга'))) {
      List<String>? header;
      for (final row in tableRows(t)) {
        final cells = row.map((c) => htmlToText(c)).toList();
        if (cells.isNotEmpty && cells.first.contains('Підчерга')) {
          header = cells.skip(1).map((s) => _gpv(s.trim())).toList();
          continue;
        }
        final day = cells.isEmpty ? null : findKyivDate(cells.first);
        if (header == null || day == null) continue;
        final values = cells.skip(1).toList();
        if (values.every((v) => v.contains('Очікується'))) continue;
        byDay[day] = {
          for (var i = 0; i < header.length && i < values.length; i++)
            header[i]: spansInText(values[i]),
        };
      }
    }
    return scheduleFromSpans(byDay, source: 'roe.vsei.ua');
  }
}

/// Прикарпаттяобленерго: графік по черзі (JSON).
class _IvanoFrankivsk extends RegionalProvider {
  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final q = queueShort(a.queue);
    final d = await Net.json('https://be-svitlo.oe.if.ua/schedule-by-queue?queue=$q', headers: {
      'Origin': 'https://svitlo.oe.if.ua',
      'Referer': 'https://svitlo.oe.if.ua/',
    });
    final rows = d is Map ? (d['schedule'] as List? ?? const []) : (d is List ? d : const []);
    final byDay = <int, Map<String, List<Span>>>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final day = findKyivDate('${r['eventDate']}');
      final periods = (r['queues'] is Map ? r['queues'][q] : null) as List?;
      if (day == null || periods == null) continue;
      byDay[day] = {
        a.queue: [
          for (final p in periods)
            Span(
              parseHm('${p['from']}') ?? 0,
              parseHm('${p['to']}') ?? 0,
              '${p['status']}'.toLowerCase().contains('prob') ? Power.maybe : Power.off,
            ),
        ],
      };
    }
    return scheduleFromSpans(byDay, source: 'svitlo.oe.if.ua');
  }
}

/// Запоріжжяобленерго: дописи «ГРАФІКИ ПОГОДИННИХ ВІДКЛЮЧЕНЬ НА 13 ЖОВТНЯ».
class _Zaporizhzhia extends RegionalProvider {
  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final text = htmlToText(await Net.text('https://www.zoe.com.ua/outage/',
        via: await Net.withIntermediates()));
    final today = kyivToday();
    final byDay = <int, Map<String, List<Span>>>{};
    final heads = RegExp(r'^.*(ГПВ|ПОГОДИННИХ ВІДКЛЮЧЕНЬ).*$', multiLine: true, caseSensitive: false)
        .allMatches(text)
        .toList();
    for (var i = 0; i < heads.length; i++) {
      final day = findKyivDate(heads[i][0]!);
      if (day == null || day < today || byDay.containsKey(day)) continue;
      final end = i + 1 < heads.length ? heads[i + 1].start : text.length;
      final block = text.substring(heads[i].end, end);
      if (heads[i][0]!.toUpperCase().contains('НЕ ЗАПЛАНОВАН')) {
        byDay[day] = {for (final q in standardQueues) q: <Span>[]};
        continue;
      }
      final queues = parseQueueLines(block);
      if (queues.isNotEmpty) {
        byDay[day] = {for (final q in standardQueues) q: queues[q] ?? <Span>[]};
      }
    }
    return scheduleFromSpans(byDay, source: 'zoe.com.ua');
  }
}

/// Закарпаттяобленерго: сторінка «Актуалізована інформація».
class _Zakarpattia extends RegionalProvider {
  @override
  Future<RegionSchedule> schedule(SavedAddress a) async {
    final html = await Net.text(
        'https://zakarpat.energy/customers/break-in-electricity-supply/updated-information/');
    final main = RegExp(r'<main[\s\S]*?</main>').firstMatch(html)?[0] ?? html;
    final text = htmlToText(main);
    final queues = parseQueueLines(text);
    if (queues.isEmpty) return scheduleFromSpans({}, source: 'zakarpat.energy');
    final day = findKyivDate(text.substring(text.indexOf('наведено').clamp(0, text.length))) ??
        kyivToday();
    return scheduleFromSpans(
      {day: {for (final q in standardQueues) q: queues[q] ?? <Span>[]}},
      source: 'zakarpat.energy',
    );
  }
}
