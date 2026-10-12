import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'regions.dart';

class ScheduleLoadException implements Exception {
  final String message;
  ScheduleLoadException(this.message);
  @override
  String toString() => message;
}

class LoadResult {
  final RegionSchedule schedule;

  /// true — мережі немає, показуємо останні збережені дані.
  final bool fromCache;
  const LoadResult(this.schedule, {this.fromCache = false});
}

class DtekService {
  DtekService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
    'Accept-Language': 'uk-UA,uk;q=0.9',
  };

  /// Спершу сайт DTEK, якщо він закритий антиботом — дзеркало,
  /// якщо немає мережі — кеш.
  Future<LoadResult> load(DtekRegion region) async {
    final errors = <String>[];

    try {
      final raw = await _fetchFromDtekSite(region);
      await _saveCache(region, raw);
      return LoadResult(_parse(raw));
    } catch (e) {
      errors.add('сайт DTEK: $e');
    }

    if (region.mirrorUrl != null) {
      try {
        final raw = await _fetchFromMirror(region);
        await _saveCache(region, raw);
        return LoadResult(_parse(raw));
      } catch (e) {
        errors.add('дзеркало: $e');
      }
    }

    final cached = await _loadCache(region);
    if (cached != null) return LoadResult(_parse(cached), fromCache: true);

    throw ScheduleLoadException(
      'Не вдалося завантажити графік.\n${errors.join('\n')}',
    );
  }

  Future<Map<String, dynamic>> _fetchFromDtekSite(DtekRegion region) async {
    final res = await _client
        .get(Uri.parse(region.shutdownsUrl), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ScheduleLoadException('HTTP ${res.statusCode}');
    }
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);
    final fact = extractJsObject(html, 'DisconSchedule.fact');
    if (fact == null) {
      // Сторінка-заглушка Incapsula замість сайту.
      throw ScheduleLoadException('сайт закритий захистом від ботів');
    }
    return {
      'fact': jsonDecode(fact),
      'preset': _tryDecode(extractJsObject(html, 'DisconSchedule.preset')),
      'source': Uri.parse(region.shutdownsUrl).host.replaceFirst('www.', ''),
    };
  }

  Future<Map<String, dynamic>> _fetchFromMirror(DtekRegion region) async {
    final res = await _client
        .get(Uri.parse(region.mirrorUrl!))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ScheduleLoadException('HTTP ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return {
      'fact': json['fact'],
      'preset': json['preset'],
      'source': 'DTEK через outage-data-ua',
    };
  }

  RegionSchedule _parse(Map<String, dynamic> raw) {
    final fact = raw['fact'];
    if (fact is! Map) throw ScheduleLoadException('невідомий формат даних');
    final preset = raw['preset'];
    return RegionSchedule.fromDtek(
      Map<String, dynamic>.from(fact),
      preset is Map ? Map<String, dynamic>.from(preset) : null,
      source: '${raw['source'] ?? 'DTEK'}',
    );
  }

  static dynamic _tryDecode(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(DtekRegion region, Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_${region.id}', jsonEncode(raw));
  }

  Future<Map<String, dynamic>?> _loadCache(DtekRegion region) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('cache_${region.id}');
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }
}

/// Знаходить `marker = { ... }` у HTML і повертає JSON-об'єкт цілком,
/// рахуючи дужки з урахуванням рядків.
String? extractJsObject(String html, String marker) {
  final m = RegExp('${RegExp.escape(marker)}\\s*=\\s*').firstMatch(html);
  if (m == null) return null;
  final start = m.end;
  if (start >= html.length || html[start] != '{') return null;

  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < html.length; i++) {
    final c = html[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return html.substring(start, i + 1);
    }
  }
  return null;
}
