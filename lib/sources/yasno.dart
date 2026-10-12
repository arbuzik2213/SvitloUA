import 'dart:convert';

import 'package:http/http.dart' as http;

import '../address.dart';
import '../models.dart';
import '../regions.dart';

/// Публічне API Yasno: пошук адреси і графік для Києва та Дніпропетровщини.
class YasnoApi {
  YasnoApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _base =
      'https://app.yasno.ua/api/blackout-service/public/shutdowns';

  Future<dynamic> _get(String path, Map<String, Object?> params) async {
    final uri = Uri.parse('$_base/$path').replace(queryParameters: {
      for (final e in params.entries)
        if (e.value != null) e.key: '${e.value}',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('Yasno: HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  List<AddressOption> _options(dynamic json,
          [Map<String, dynamic> extra = const {}]) =>
      [
        if (json is List)
          for (final o in json)
            AddressOption('${o['id']}', '${o['value']}'.trim(), extra),
      ];

  /// Населені пункти: шукаємо в усіх операторах області й запамʼятовуємо,
  /// чий це пункт.
  Future<List<AddressOption>> cities(Oblast o, String query) async {
    final results = await Future.wait([
      for (final dso in o.yasnoDsos)
        _get('addresses/v2/cities', {
          'regionId': o.yasnoRegion,
          'dsoId': dso,
          'query': query,
        }).then((j) => _options(j, {'dso': dso})),
    ]);
    return results.expand((e) => e).toList();
  }

  int _dso(Oblast o, AddressOption? city) =>
      (city?.extra['dso'] as int?) ?? o.yasnoDsos.first;

  Future<List<AddressOption>> streets(
      Oblast o, AddressOption? city, String query) async {
    final dso = _dso(o, city);
    return _options(
      await _get('addresses/v2/streets', {
        'regionId': o.yasnoRegion,
        'dsoId': dso,
        'cityId': city?.id,
        'query': query,
      }),
      {'dso': dso},
    );
  }

  Future<List<AddressOption>> houses(
    Oblast o,
    AddressOption? city,
    AddressOption street,
    String query,
  ) async {
    final dso = _dso(o, city);
    return _options(
      await _get('addresses/v2/houses', {
        'regionId': o.yasnoRegion,
        'dsoId': dso,
        'cityId': city?.id,
        'streetId': street.id,
        'query': query,
      }),
      {'dso': dso},
    );
  }

  /// Черга будинку у форматі DTEK (GPV20.1).
  Future<String?> queue(
    Oblast o,
    AddressOption? city,
    AddressOption street,
    AddressOption house,
  ) async {
    final j = await _get('addresses/v2/group', {
      'regionId': o.yasnoRegion,
      'dsoId': _dso(o, city),
      'cityId': city?.id,
      'streetId': street.id,
      'houseId': house.id,
    });
    if (j is! Map || j['group'] == null) return null;
    return 'GPV${j['group']}.${j['subgroup'] ?? 1}';
  }

  /// Сирий графік усіх черг оператора на сьогодні й завтра
  /// (розбирає [parseYasnoSchedule]; сирим зберігаємо в кеш).
  Future<Map<String, dynamic>> scheduleRaw(Oblast o, int dso) async {
    final j = await _get(
      'regions/${o.yasnoRegion}/dsos/$dso/planned-outages',
      const {},
    );
    if (j is! Map) throw Exception('Yasno: порожня відповідь');
    return Map<String, dynamic>.from(j);
  }
}

/// Формат Yasno: { "20.1": { "today": { "date", "status", "slots": [
/// {start, end, type}] }, "tomorrow": ..., "updatedOn" } },
/// де start/end — хвилини від початку дня, type — Definite / NotPlanned.
RegionSchedule parseYasnoSchedule(Map<String, dynamic> json) {
  final days = <int, Map<String, DaySchedule>>{};
  final names = <String, String>{};
  int? today;
  var updated = '';

  json.forEach((group, value) {
    if (value is! Map) return;
    final key = 'GPV$group';
    names[key] = 'Черга $group';
    final u = value['updatedOn'];
    if (u is String && u.compareTo(updated) > 0) updated = u;

    for (final dayName in const ['today', 'tomorrow']) {
      final day = value[dayName];
      if (day is! Map || day['date'] == null) continue;
      // Графік на завтра ще не опубліковано — не показуємо порожній день.
      if (day['status'] == 'WaitingForSchedule') continue;

      final start =
          DateTime.parse('${day['date']}').millisecondsSinceEpoch ~/ 1000;
      if (dayName == 'today') today = start;
      final slots = List.filled(48, Power.on);
      for (final s in (day['slots'] as List? ?? const [])) {
        if (s is! Map) continue;
        final power = switch (s['type']) {
          'NotPlanned' => Power.on,
          'Definite' => Power.off,
          _ => Power.maybe,
        };
        final from = ((s['start'] as num).toInt() ~/ 30).clamp(0, 48);
        final to = ((s['end'] as num).toInt() / 30).ceil().clamp(0, 48);
        for (var i = from; i < to; i++) {
          slots[i] = power;
        }
      }
      (days[start] ??= {})[key] = DaySchedule(start, slots);
    }
  });

  final sortedNames = names.keys.toList()..sort(compareQueues);
  return RegionSchedule(
    queueNames: {for (final k in sortedNames) k: names[k]!},
    days: days,
    updated: updated.isEmpty ? '' : _formatUpdated(updated),
    today: today ?? 0,
    source: 'Yasno',
  );
}

String _formatUpdated(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final unix = t.millisecondsSinceEpoch ~/ 1000;
  return '${kyivTime(unix)} ${kyivShortDate(unix)}';
}
