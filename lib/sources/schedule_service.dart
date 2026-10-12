import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../address.dart';
import '../models.dart';
import '../regions.dart';
import 'dtek_bridge.dart';
import 'yasno.dart';

class LoadResult {
  final RegionSchedule schedule;

  /// true — мережі немає, показуємо останні збережені дані.
  final bool fromCache;

  /// Поточне аварійне чи планове відключення саме цього будинку (DTEK).
  final String? notice;

  const LoadResult(this.schedule, {this.fromCache = false, this.notice});
}

/// Завантажує графік для адреси: основне джерело → дзеркало → кеш.
class ScheduleService {
  ScheduleService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  late final _yasno = YasnoApi(client: _client);

  Future<LoadResult> load(Oblast oblast, SavedAddress? address) async {
    final errors = <String>[];
    final dso = address?.street.extra['dso'] as int? ??
        (oblast.yasnoDsos.isEmpty ? null : oblast.yasnoDsos.first);
    final cacheKey = 'sched_${oblast.id}_${dso ?? ''}';

    if (oblast.kind == SourceKind.yasno && dso != null) {
      try {
        final raw = await _yasno.scheduleRaw(oblast, dso);
        final s = parseYasnoSchedule(raw);
        await _save(cacheKey, {'yasno': true, 'schedule': raw});
        return LoadResult(s);
      } catch (e) {
        errors.add('Yasno: $e');
      }
    }

    if (oblast.kind == SourceKind.dtek && DtekBridge.supported) {
      try {
        final raw = await DtekBridge.instance.schedule(oblast.dtekUrl!);
        raw['source'] =
            Uri.parse(oblast.dtekUrl!).host.replaceFirst('www.', '');
        await _save(cacheKey, raw);
        return LoadResult(_parseDtek(raw),
            notice: await _notice(oblast, address));
      } catch (e) {
        errors.add('сайт DTEK: $e');
      }
    }

    // Дзеркало містить дані DTEK; для ЦЕК (Yasno dso 303) воно не підходить.
    if (oblast.mirrorUrl != null && dso != 303) {
      try {
        final res = await _client
            .get(Uri.parse(oblast.mirrorUrl!))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final raw = {
          'fact': json['fact'],
          'preset': json['preset'],
          'source': 'DTEK через outage-data-ua',
        };
        await _save(cacheKey, raw);
        return LoadResult(_parseDtek(raw));
      } catch (e) {
        errors.add('дзеркало: $e');
      }
    }

    final cached = await _load(cacheKey);
    if (cached != null) {
      final s = cached['yasno'] == true
          ? parseYasnoSchedule(
              Map<String, dynamic>.from(cached['schedule'] as Map))
          : _parseDtek(cached);
      return LoadResult(s, fromCache: true);
    }

    throw Exception('Не вдалося завантажити графік.\n${errors.join('\n')}');
  }

  /// DTEK повертає для будинку поточне відключення: тип і час.
  Future<String?> _notice(Oblast oblast, SavedAddress? a) async {
    if (a == null) return null;
    try {
      final houses = await DtekBridge.instance
          .houses(oblast.dtekUrl!, a.city?.id ?? '', a.street.id);
      final h = houses[a.house.id];
      final type = '${h?['sub_type'] ?? ''}'.trim();
      if (type.isEmpty) return null;
      final start = '${h?['start_date'] ?? ''}'.trim();
      final end = '${h?['end_date'] ?? ''}'.trim();
      return [
        type,
        if (start.isNotEmpty) 'з $start',
        if (end.isNotEmpty) 'орієнтовно до $end',
      ].join('\n');
    } catch (_) {
      return null;
    }
  }

  RegionSchedule _parseDtek(Map<String, dynamic> raw) {
    final fact = raw['fact'];
    if (fact is! Map) throw Exception('невідомий формат даних');
    final preset = raw['preset'];
    return RegionSchedule.fromDtek(
      Map<String, dynamic>.from(fact),
      preset is Map ? Map<String, dynamic>.from(preset) : null,
      source: '${raw['source'] ?? 'DTEK'}',
    );
  }

  Future<void> _save(String key, Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(raw));
  }

  Future<Map<String, dynamic>?> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(key);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }
}
