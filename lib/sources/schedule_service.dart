import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../address.dart';
import '../models.dart';
import '../regions.dart';
import 'common.dart';
import 'dtek_bridge.dart';
import 'regional.dart';
import 'yasno.dart';

class LoadResult {
  final RegionSchedule schedule;

  /// true — мережі немає, показуємо останні збережені дані.
  final bool fromCache;

  /// Поточне аварійне чи планове відключення саме цього будинку.
  final String? notice;

  const LoadResult(this.schedule, {this.fromCache = false, this.notice});
}

/// Завантажує графік для адреси: основне джерело → дзеркало → кеш.
class ScheduleService {
  final _yasno = YasnoApi(client: Net.client);

  Future<LoadResult> load(Oblast oblast, SavedAddress? address) async {
    final errors = <String>[];
    final dso = address?.path
            .map((o) => o.extra['dso'])
            .whereType<int>()
            .firstOrNull ??
        oblast.yasnoDsos.firstOrNull;
    final cacheKey =
        'sched3_${oblast.id}_${dso ?? ''}_${address?.queue ?? ''}';

    Future<LoadResult> ok(RegionSchedule s, {String? notice}) async {
      await _save(cacheKey, s);
      return LoadResult(s, notice: notice);
    }

    switch (oblast.kind) {
      case RegionKind.yasno:
        try {
          return await ok(
              parseYasnoSchedule(await _yasno.scheduleRaw(oblast, dso!)));
        } catch (e) {
          errors.add('Yasno: $e');
        }
      case RegionKind.dtek:
        if (DtekBridge.supported) {
          try {
            final raw = await DtekBridge.instance.schedule(oblast.dtekUrl!);
            return await ok(
              _parseDtek(raw,
                  Uri.parse(oblast.dtekUrl!).host.replaceFirst('www.', '')),
              notice: await _dtekNotice(oblast, address),
            );
          } catch (e) {
            errors.add('сайт DTEK: $e');
          }
        }
      case RegionKind.native:
        final p = regionalProvider(oblast.id);
        if (p != null && address != null) {
          String? notice;
          try {
            notice = await p.notice(address);
          } catch (_) {}
          if (!oblast.schedule) {
            return LoadResult(
              RegionSchedule(
                queueNames: const {},
                days: const {},
                updated: '',
                today: kyivToday(),
                source: Uri.parse(oblast.webUrl).host,
              ),
              notice: notice,
            );
          }
          try {
            return await ok(await p.schedule(address), notice: notice);
          } catch (e) {
            errors.add('${Uri.parse(oblast.webUrl).host}: $e');
          }
        }
      case RegionKind.web:
        break;
    }

    // Дзеркало містить дані DTEK; для ЦЕК (Yasno dso 303) воно не підходить.
    if (oblast.mirrorUrl != null && dso != 303) {
      try {
        final json = await Net.json(oblast.mirrorUrl!) as Map<String, dynamic>;
        return await ok(_parseDtek(
          {'fact': json['fact'], 'preset': json['preset']},
          'DTEK через outage-data-ua',
        ));
      } catch (e) {
        errors.add('дзеркало: $e');
      }
    }

    final cached = await _load(cacheKey);
    if (cached != null) return LoadResult(cached, fromCache: true);

    throw Exception('Не вдалося завантажити графік.\n${errors.join('\n')}');
  }

  /// DTEK повертає для будинку поточне відключення: тип і час.
  Future<String?> _dtekNotice(Oblast oblast, SavedAddress? a) async {
    if (a == null || a.path.length < 3) return null;
    try {
      final houses = await DtekBridge.instance
          .houses(oblast.dtekUrl!, a.path[0].id, a.path[1].id);
      final h = houses[a.path.last.id];
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

  RegionSchedule _parseDtek(Map<String, dynamic> raw, String source) {
    final fact = raw['fact'];
    if (fact is! Map) throw Exception('невідомий формат даних');
    final preset = raw['preset'];
    return RegionSchedule.fromDtek(
      Map<String, dynamic>.from(fact),
      preset is Map ? Map<String, dynamic>.from(preset) : null,
      source: source,
    );
  }

  Future<void> _save(String key, RegionSchedule s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(s.toJson()));
  }

  Future<RegionSchedule?> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(key);
    if (s == null) return null;
    try {
      return RegionSchedule.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
