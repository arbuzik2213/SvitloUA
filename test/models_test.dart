import 'package:flutter_test/flutter_test.dart';
import 'package:svitlo_ua/dtek_service.dart';
import 'package:svitlo_ua/models.dart';

void main() {
  // 12.10.2026 00:00 за Києвом (UTC+3).
  const day = 1791752400;

  Map<String, dynamic> hours(Map<int, String> special) =>
      {for (var h = 1; h <= 24; h++) '$h': special[h] ?? 'yes'};

  test('витягує DisconSchedule.fact з HTML DTEK', () {
    const html = '<script>DisconSchedule.fact = {"data":[],"update":"x}","today":1}'
        '</script><script>DisconSchedule.preset = {"a":{"b":"}"}}\n</script>';
    expect(extractJsObject(html, 'DisconSchedule.fact'),
        '{"data":[],"update":"x}","today":1}');
    expect(extractJsObject(html, 'DisconSchedule.preset'), '{"a":{"b":"}"}}');
    expect(extractJsObject('<html></html>', 'DisconSchedule.fact'), isNull);
  });

  test('розбирає години DTEK на інтервали', () {
    final s = RegionSchedule.fromDtek({
      'data': {
        '$day': {
          'GPV1.1': hours({1: 'no', 2: 'no', 3: 'no', 4: 'first', 18: 'second', 19: 'no'}),
          'GPV10.1': hours({}),
          'GPV2.1': hours({}),
        },
      },
      'update': '12.10.2026 15:00',
      'today': day,
    }, null, source: 'test');

    expect(s.queueNames.keys, ['GPV1.1', 'GPV2.1', 'GPV10.1']);

    final iv = s.intervalsFor('GPV1.1');
    final off = iv.where((i) => i.power == Power.off).toList();
    expect(off.length, 2);
    expect(kyivTime(off[0].start), '00:00');
    expect(kyivTime(off[0].end), '03:30');
    expect(kyivTime(off[1].start), '17:30');
    expect(kyivTime(off[1].end), '19:00');

    final st = QueueStatus.compute(iv, day + 3600 * 10); // 10:00
    expect(st.current!.power, Power.on);
    expect(kyivTime(st.nextOff!.start), '17:30');
  });

  test('порожній список data означає відсутність відключень', () {
    final s = RegionSchedule.fromDtek(
        {'data': [], 'update': '', 'today': day}, null,
        source: 'test');
    expect(s.days, isEmpty);
  });

  test('київський час з урахуванням зимового часу', () {
    expect(kyivTime(day), '00:00');
    // 1 січня 2026 00:00 UTC = 02:00 за Києвом.
    expect(kyivTime(1767225600), '02:00');
    expect(kyivDate(day), '12 жовтня, понеділок');
  });
}
