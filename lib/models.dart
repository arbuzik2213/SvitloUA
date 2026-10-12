/// Стан електропостачання в одному 30-хвилинному слоті.
enum Power { on, off, maybe }

/// Один інтервал з однаковим станом. Час — секунди Unix.
class PowerInterval {
  final int start;
  final int end;
  final Power power;
  const PowerInterval(this.start, this.end, this.power);

  int get duration => end - start;
}

/// Графік дня для однієї черги: 48 слотів по 30 хвилин.
class DaySchedule {
  /// Північ цього дня за Києвом, секунди Unix (ключ із даних DTEK).
  final int dayStart;
  final List<Power> slots;
  const DaySchedule(this.dayStart, this.slots);

  /// DTEK описує кожну годину одним із кодів: yes, no, first, second,
  /// maybe, mfirst, msecond. Розкладаємо годину на два півгодинні слоти.
  static List<Power> hourToSlots(String? code) {
    switch (code) {
      case 'no':
        return const [Power.off, Power.off];
      case 'first':
        return const [Power.off, Power.on];
      case 'second':
        return const [Power.on, Power.off];
      case 'maybe':
        return const [Power.maybe, Power.maybe];
      case 'mfirst':
        return const [Power.maybe, Power.on];
      case 'msecond':
        return const [Power.on, Power.maybe];
      default:
        return const [Power.on, Power.on];
    }
  }

  factory DaySchedule.fromDtekHours(int dayStart, Map<String, dynamic> hours) {
    final slots = <Power>[];
    for (var h = 1; h <= 24; h++) {
      slots.addAll(hourToSlots(hours['$h'] as String?));
    }
    return DaySchedule(dayStart, slots);
  }

  int get offSeconds => slots.where((s) => s == Power.off).length * 1800;
}

/// Розібрані дані DTEK для регіону.
class RegionSchedule {
  /// GPV1.1 -> "Черга 1.1", у правильному порядку.
  final Map<String, String> queueNames;

  /// Ключ — північ дня (Unix), значення — графік кожної черги.
  final Map<int, Map<String, DaySchedule>> days;

  /// Текст «оновлено» з сайту DTEK.
  final String updated;
  final int today;
  final String source;

  const RegionSchedule({
    required this.queueNames,
    required this.days,
    required this.updated,
    required this.today,
    required this.source,
  });

  /// [fact] і [preset] — об'єкти DisconSchedule.fact / DisconSchedule.preset.
  factory RegionSchedule.fromDtek(
    Map<String, dynamic> fact,
    Map<String, dynamic>? preset, {
    required String source,
  }) {
    final days = <int, Map<String, DaySchedule>>{};
    final data = fact['data'];
    // Коли відключень немає, DTEK віддає порожній список замість мапи.
    if (data is Map) {
      data.forEach((dayKey, queues) {
        final dayStart = int.tryParse('$dayKey');
        if (dayStart == null || queues is! Map) return;
        days[dayStart] = {
          for (final e in queues.entries)
            if (e.value is Map)
              '${e.key}': DaySchedule.fromDtekHours(
                dayStart,
                Map<String, dynamic>.from(e.value as Map),
              ),
        };
      });
    }

    final names = <String, String>{};
    final presetNames = preset?['sch_names'];
    if (presetNames is Map) {
      presetNames.forEach((k, v) => names['$k'] = '$v');
    }
    for (final day in days.values) {
      for (final q in day.keys) {
        names.putIfAbsent(q, () => 'Черга ${q.replaceFirst('GPV', '')}');
      }
    }
    final sortedKeys = names.keys.toList()..sort(compareQueues);

    return RegionSchedule(
      queueNames: {for (final k in sortedKeys) k: names[k]!},
      days: days,
      updated: '${fact['update'] ?? ''}',
      today: (fact['today'] as num?)?.toInt() ?? 0,
      source: source,
    );
  }

  List<int> get sortedDays => days.keys.toList()..sort();

  /// Усі слоти черги підряд (сьогодні, завтра...) як інтервали.
  List<PowerInterval> intervalsFor(String queue) {
    final result = <PowerInterval>[];
    for (final day in sortedDays) {
      final sch = days[day]![queue];
      if (sch == null) continue;
      for (var i = 0; i < sch.slots.length; i++) {
        final start = day + i * 1800;
        final p = sch.slots[i];
        if (result.isNotEmpty &&
            result.last.power == p &&
            result.last.end == start) {
          final last = result.removeLast();
          result.add(PowerInterval(last.start, start + 1800, p));
        } else {
          result.add(PowerInterval(start, start + 1800, p));
        }
      }
    }
    return result;
  }
}

/// Номер черги без префікса: GPV3.1 -> 3.1.
String queueShort(String key) => key.replaceFirst('GPV', '');

/// Сортування GPV1.1, GPV1.2, GPV2.1 ... GPV10.1 за числами, а не рядком.
int compareQueues(String a, String b) {
  List<int> parts(String s) => RegExp(r'\d+')
      .allMatches(s)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return pa.length != pb.length ? pa.length.compareTo(pb.length) : a.compareTo(b);
}

/// Стан зараз і найближча зміна для вибраної черги.
class QueueStatus {
  final PowerInterval? current;
  final PowerInterval? nextOff;
  const QueueStatus(this.current, this.nextOff);

  static QueueStatus compute(List<PowerInterval> intervals, int now) {
    PowerInterval? current;
    PowerInterval? nextOff;
    for (final iv in intervals) {
      if (iv.start <= now && now < iv.end) current = iv;
      if (iv.start > now && iv.power == Power.off && nextOff == null) {
        nextOff = iv;
      }
    }
    return QueueStatus(current, nextOff);
  }
}

/// Час Unix → "HH:MM" за Києвом.
String kyivTime(int unix) {
  final t = toKyiv(unix);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

const _weekdays = ['понеділок', 'вівторок', 'середа', 'четвер', 'пʼятниця', 'субота', 'неділя'];
const _months = [
  'січня', 'лютого', 'березня', 'квітня', 'травня', 'червня',
  'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня',
];

/// "12 жовтня, понеділок"
String kyivDate(int unix) {
  final t = toKyiv(unix);
  return '${t.day} ${_months[t.month - 1]}, ${_weekdays[t.weekday - 1]}';
}

/// "12.10"
String kyivShortDate(int unix) {
  final t = toKyiv(unix);
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
}

/// Перевід у київський час без пакета з часовими поясами: Україна
/// використовує європейські правила літнього часу (остання неділя березня
/// і жовтня, 01:00 UTC).
DateTime toKyiv(int unix) {
  final utc = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
  DateTime lastSunday(int year, int month) {
    var d = DateTime.utc(year, month + 1, 0, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  final summer = !utc.isBefore(lastSunday(utc.year, 3)) &&
      utc.isBefore(lastSunday(utc.year, 10));
  return utc.add(Duration(hours: summer ? 3 : 2));
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '$m хв';
  if (m == 0) return '$h год';
  return '$h год $m хв';
}
